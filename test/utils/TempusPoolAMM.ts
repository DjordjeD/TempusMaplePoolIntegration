import { Contract } from "ethers";
import { NumberOrString, toWei } from "./Decimal";
import { ContractBase, Signer } from "./ContractBase";
import { AMP_PRECISION, MONTH, TempusAMM, TempusAMMJoinKind } from "./TempusAMM";
import { PoolShare } from "./PoolShare";
import { TempusController } from "./TempusController";

/**
 * Wrapper for TempusAMM with principal and yield
 */
export class TempusPoolAMM extends TempusAMM {

  principalShare: PoolShare;
  yieldShare: PoolShare;

  constructor(tempusAmmPool: Contract, vault: Contract, principalShare: PoolShare, yieldShare: PoolShare) {
    super(tempusAmmPool, vault, principalShare, yieldShare);

    this.principalShare = principalShare;
    this.yieldShare = yieldShare;
  }

  static async create(
    owner: Signer,
    controller: TempusController,
    principalShare: PoolShare,
    yieldShare: PoolShare,
    rawAmplificationStart: number,
    rawAmplificationEnd: number,
    amplificationEndTime: number,
    swapFeePercentage: number
  ): Promise<TempusPoolAMM> {
    const mockedWETH = await TempusAMM.createMock();

    const authorizer = await ContractBase.deployContract("@balancer-labs/v2-vault/contracts/Authorizer.sol:Authorizer", owner.address);
    const vault = await ContractBase.deployContract("@balancer-labs/v2-vault/contracts/Vault.sol:Vault", authorizer.address, mockedWETH.address, 3 * MONTH, MONTH);

    let tempusAMM = await ContractBase.deployContractBy(
      "TempusAMM",
      owner,
      vault.address, 
      "Tempus LP token", 
      "LP",
      [principalShare.address, yieldShare.address],
      +rawAmplificationStart * AMP_PRECISION,
      +rawAmplificationEnd * AMP_PRECISION,
      amplificationEndTime,
      toWei(swapFeePercentage),
      3 * MONTH, 
      MONTH, 
      owner.address
    );
    
    await controller.register(owner, tempusAMM.address);
    return new TempusPoolAMM(tempusAMM, vault, principalShare, yieldShare);
  }
  
  public getPYAmounts(token0Amount: NumberOrString, token1Amount: NumberOrString): {principalsAmount:number, yieldsAmount:number} {
    return (this.principalShare.address == this.token0.address)
      ? {principalsAmount: +token0Amount, yieldsAmount: +token1Amount}
      : {principalsAmount: +token1Amount, yieldsAmount: +token0Amount};
  }

  async getExpectedPYOutGivenBPTIn(inAmount: NumberOrString): Promise<{principalsOut:number, yieldsOut:number}> {
    const p = await super.getExpectedTokensOutGivenBPTIn(inAmount);
    const {principalsAmount, yieldsAmount} = this.getPYAmounts(p.token0Out, p.token1Out);
    return {principalsOut: +principalsAmount, yieldsOut: +yieldsAmount};
  }

  async getExpectedLPTokensForTokensIn(principalsAmountIn:NumberOrString, yieldsAmountIn:NumberOrString): Promise<NumberOrString> {
    const {principalsAmount, yieldsAmount} = this.getPYAmounts(principalsAmountIn, yieldsAmountIn); 
    return super.getExpectedLPTokensForTokensIn(principalsAmount, yieldsAmount);
  }

  async getExpectedBPTInGivenTokensOut(principalStaked:NumberOrString, yieldsStaked:NumberOrString): Promise<NumberOrString> {
    const {principalsAmount, yieldsAmount} = this.getPYAmounts(principalStaked, yieldsStaked); 
    return super.getExpectedBPTInGivenTokensOut(principalsAmount, yieldsAmount);
  }

  async provideLiquidity(from: Signer, principals: Number, yields: Number, joinKind: TempusAMMJoinKind) {
    const {principalsAmount, yieldsAmount} = this.getPYAmounts(principals, yields); 
    await super.provideLiquidity(from, principalsAmount, yieldsAmount, joinKind);
  }

  async exitPoolExactAmountOut(from:Signer, amountsOut:Number[], maxAmountLpIn:Number) {
    const {principalsAmount, yieldsAmount} = this.getPYAmounts(amountsOut[0], amountsOut[1]); 
    await super.exitPoolExactAmountOut(from, [principalsAmount, yieldsAmount], maxAmountLpIn);
  }
}