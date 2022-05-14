import { Contract } from "ethers";
import { ContractBase, Signer, SignerOrAddress, addressOf } from "./ContractBase";
import { Numberish } from "./Decimal";
import { ERC20 } from "./ERC20";
import { TempusAMM } from "./TempusAMM";
import { TempusPool } from "./TempusPool";
import { Stats } from "./Stats";

export class LPVault extends ERC20 {
  ybt:ERC20;

  constructor(contractName: string, decimals: number, ybt: ERC20, contract: Contract) {
    super(contractName, decimals/*default decimals*/, contract);
    this.ybt = ybt;
  }

  static async create(pool: TempusPool, amm: TempusAMM, stats: Stats, name: string, symbol: string): Promise<LPVault> {
    const lpVault = await ContractBase.deployContract("LPVaultV1", pool.address, amm.address, stats.address, name, symbol);
    return new LPVault("LPVaultV1", await lpVault.decimals(), pool.yieldBearing, lpVault);
  }

  async previewDeposit(caller: Signer, amount: Numberish): Promise<Numberish> {
    return this.ybt.fromBigNum(await this.connect(caller).previewDeposit(this.ybt.toBigNum(amount)));
  }

  async deposit(caller: Signer, amount: Numberish, recipient: SignerOrAddress): Promise<void> {
    await this.connect(caller).deposit(this.ybt.toBigNum(amount), addressOf(recipient));
  }

  async previewWithdraw(caller: Signer, shares: Numberish): Promise<Numberish> {
    return this.ybt.fromBigNum(await this.connect(caller).previewWithdraw(this.ybt.toBigNum(shares)));
  }

  async withdraw(caller: Signer, shares: Numberish, recipient: SignerOrAddress): Promise<void> {
    await this.connect(caller).withdraw(this.toBigNum(shares), addressOf(recipient));
  }

  async migrate(caller: Signer, pool: TempusPool, amm: TempusAMM, stats: Stats): Promise<void> {
    await this.connect(caller).migrate(pool.address, amm.address, stats.address);
  }

  async shutdown(caller: Signer): Promise<void> {
    await this.connect(caller).sthudown();
  }

  async totalAssets(caller: Signer): Promise<Numberish> {
    return this.ybt.fromBigNum(await this.connect(caller).totalAssets());
  }
}
