import { expect } from "chai";
import { Transaction } from "ethers";
import { Signer } from "../utils/ContractBase";
import { TempusPool } from "../utils/TempusPool";
import { ERC20 } from "../utils/ERC20";
import { NumberOrString } from "../utils/Decimal";
import { getRevertMessage } from "../utils/Utils";

export enum PoolType
{
  Aave = "Aave",
  Lido = "Lido",
  Compound = "Compound",
}

export class UserState {
  principalShares:Number;
  yieldShares:Number;
  yieldBearing:Number;

  // non-async to give us actual test failure line #
  public expect(principalShares:number, yieldShares:number, yieldBearing:number, message:string = null) {
    const msg = message === null ? "" : ": expected" + message;
    expect(this.principalShares).to.equal(principalShares, "principalShares did not match expected value"+msg);
    expect(this.yieldShares).to.equal(yieldShares, "yieldShares did not match expected value"+msg);
    expect(this.yieldBearing).to.equal(yieldBearing, "yieldBearing did not match expected value"+msg);
  }
}

export abstract class ITestPool {
  type:PoolType;
  principalName:string; // TPS
  yieldName:string; // TYS

  // if true, underlying pool pegs YieldToken 1:1 to BackingToken
  // ex true: deposit(100) with rate 1.0 will yield 100 TPS and TYS
  // ex false: deposit(100) with rate 1.2 will yield 120 TPS and TYS
  yieldPeggedToAsset:boolean;

  // initialized by createTempusPool()
  tempus:TempusPool;
  maturityTime:number;

  constructor(type:PoolType, principalName:string, yieldName:string, yieldPeggedToAsset:boolean) { 
    this.type = type;
    this.principalName = principalName;
    this.yieldName = yieldName;
    this.yieldPeggedToAsset = yieldPeggedToAsset;
  }

  /**
   * @return The underlying asset token of the backing pool
   */
  abstract asset(): ERC20;

  /**
   * @return Current Yield Bearing Token balance of the user
   */
  abstract yieldTokenBalance(user:Signer): Promise<NumberOrString>;

  /**
   * This must create the TempusPool instance
   */
  abstract createTempusPool(initialRate:number, poolDurationSeconds:number): Promise<TempusPool>;

  /**
   * @param rate Sets the Interest Rate for the underlying mock pool
   */
  abstract setExchangeRate(rate:number): Promise<void>;

  /**
   * Deposit BackingTokens into the UNDERLYING pool and receive YBT
   */
  abstract deposit(user:Signer, amount:number): Promise<void>;

  /**
   * Deposit YieldBearingTokens into TempusPool
   */
  async depositYBT(user:Signer, yieldBearingAmount:number, recipient:Signer = null): Promise<Transaction> {
    return this.tempus.deposit(user, yieldBearingAmount, (recipient !== null ? recipient : user));
  }

  /**
   * Deposit YieldBearingTokens into TempusPool, and return a testable `expect()` object.
   * This is set up so we are able to report TEST failure File and Line:
   * @example (await pool.expectDepositYBT(user, 100)).to.equal('success');
   * @returns ERROR message, or FALSE on success
   */
  async expectDepositYBT(user:Signer, yieldBearingAmount:number, recipient:Signer = null): Promise<Chai.Assertion> {
    try {
      await this.depositYBT(user, yieldBearingAmount, recipient);
      return expect('success');
    } catch(e) {
      return expect(getRevertMessage(e));
    }
  }

  /**
   * Typical setup call for most tests
   * 1. Deposits Asset into underlying pool by Owner
   * 1. Transfers Assets from Owner to depositors[]
   * 2. Transfers YBT from Owner to depositors[]
   */
  async setupAccounts(owner:Signer, depositors:[Signer,number][]): Promise<void> {
    if (!this.tempus)
      throw new Error('setupAccounts: createTempusPool not called');

    const totalDeposit = depositors.reduce((sum, current) => sum + current[1], 500);
    await this.deposit(owner, totalDeposit);

    for (let depositor of depositors) { // initial deposit for users
      const user = depositor[0];
      const amount = depositor[1];
      await this.asset().transfer(owner, user, 10000); // TODO: make this a parameter?
      await this.tempus.yieldBearing.transfer(owner, user, amount);
    }
  }

  /**
   * @returns Balances state for a single user
   */
  async userState(user:Signer): Promise<UserState> {
    let state = new UserState();
    state.principalShares = Number(await this.tempus.principalShare.balanceOf(user));
    state.yieldShares = Number(await this.tempus.yieldShare.balanceOf(user));
    state.yieldBearing = Number(await this.yieldTokenBalance(user));
    return state;
  }
}

