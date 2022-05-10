import { expect } from "chai";
import { BigNumber, ethers } from "ethers";
import { Signer } from "./utils/ContractBase";
import { TempusPool } from "./utils/TempusPool";
import { evmMine, evmSetAutomine, expectRevert, increaseTime } from "./utils/Utils";
import { TempusAMM } from "./utils/TempusAMM";
import { describeForEachPool } from "./pool-utils/MultiPoolTestSuite";
import { PoolTestFixture } from "./pool-utils/PoolTestFixture";
import { TempusPoolAMM } from "./utils/TempusPoolAMM";
import { PoolShare, ShareKind } from "./utils/PoolShare";
import { LPVault } from "./utils/LPVault";
import { Stats } from "./utils/Stats";

interface CreateParams {
  yieldEst:number;
  duration:number;
  amplifyStart:number;
  amplifyEnd:number;
  oneAmpUpdate?:number;
  ammBalanceYield?: number;
  ammBalancePrincipal?:number;
}

describeForEachPool("LPVault", (testFixture:PoolTestFixture) =>
{
  let owner:Signer, user:Signer, user1:Signer;
  const SWAP_FEE_PERC:number = 0.02;
  const ONE_HOUR:number = 60*60;
  const ONE_DAY:number = ONE_HOUR*24;
  const ONE_MONTH:number = ONE_DAY*30;
  const ONE_YEAR:number = ONE_MONTH*12;
  const ONE_AMP_UPDATE_TIME:number = ONE_DAY;

  let stats:Stats;
  let lpVault:LPVault;
  
  async function createPools(params:CreateParams): Promise<{pool:TempusPool, amm:TempusAMM}> {
    const tempusPool = await testFixture.createWithAMM({
      initialRate:1.0, poolDuration:params.duration, yieldEst:params.yieldEst,
      ammSwapFee:SWAP_FEE_PERC,
      ammAmplifyStart: params.amplifyStart,
      ammAmplifyEnd: params.amplifyStart /*NOTE: using Start value here to not trigger update yet */
    });

    const tempusAMM = testFixture.amm;
    [owner, user, user1] = testFixture.signers;

    await testFixture.setupAccounts(owner, [[owner, 100_000], [user, 100_000]]);

    const depositAmount = 1_000_000;
    await testFixture.deposit(owner, depositAmount);
    await tempusPool.controller.depositYieldBearing(owner, tempusPool, depositAmount, owner);
    if (params.ammBalanceYield != undefined && params.ammBalancePrincipal != undefined) {
      await tempusAMM.provideLiquidity(owner, params.ammBalancePrincipal, params.ammBalanceYield);
    }
    if (params.amplifyStart != params.amplifyEnd) {
      const oneAmplifyUpdate = (params.oneAmpUpdate === undefined) ? ONE_AMP_UPDATE_TIME : params.oneAmpUpdate;
      await tempusAMM.startAmplificationUpdate(params.amplifyEnd, oneAmplifyUpdate);
    }

    return {pool: tempusPool, amm: tempusAMM};
  }

  async function createVault(pool: TempusPool, amm: TempusAMM): Promise<void> {
    stats = await Stats.create();
    lpVault = await LPVault.create(pool, amm, stats, "Tempus LP Vault", "PVALT");
  }

  it("Smoke test", async () => {
    const pool = await createPools({yieldEst:0.1, duration:ONE_MONTH, amplifyStart:5, amplifyEnd:5, ammBalancePrincipal: 10_000, ammBalanceYield: 100_000});
    console.log(await testFixture.userState(pool.amm.address));
    await createVault(pool.pool, pool.amm);
    console.log(await testFixture.userState(owner));
    expect(await lpVault.balanceOf(owner)).to.equal(0);
    await lpVault.ybt.approve(owner, lpVault.address, 200);
    await lpVault.deposit(owner, 100, owner);
    console.log("after1 amm", await testFixture.userState(pool.amm.address));
    console.log("after1 lpv", await testFixture.userState(lpVault.address));
    console.log(+await lpVault.balanceOf(owner));
    expect(+await lpVault.balanceOf(owner)).to.be.within(99.9999, 100.0002);
    await lpVault.deposit(owner, 100, owner);
    console.log("after2 lpv", await testFixture.userState(lpVault.address));
    console.log(+await lpVault.balanceOf(owner));
    expect(+await lpVault.balanceOf(owner)).to.be.within(199.9999, 200.0002);
    await lpVault.withdraw(owner, 100, owner);
    console.log("after3 lpv", await testFixture.userState(lpVault.address));
    expect(+await lpVault.balanceOf(owner)).to.be.within(99.9999, 100.0002);
  });

  it("Early migrate", async () => {
    const pool = await createPools({yieldEst:0.1, duration:ONE_MONTH, amplifyStart:5, amplifyEnd:5, ammBalancePrincipal: 10000, ammBalanceYield: 100000});
    await createVault(pool.pool, pool.amm);
    (await expectRevert(lpVault.migrate(owner, pool.pool, pool.amm, stats)))
      .to.equal("Current Pool has not matured yet");
  });

  it("Migrate to self", async () => {
    const pool = await createPools({yieldEst:0.1, duration:ONE_MONTH, amplifyStart:5, amplifyEnd:5, ammBalancePrincipal: 10000, ammBalanceYield: 100000});
    await createVault(pool.pool, pool.amm);
    await increaseTime(2 * ONE_MONTH);
    await pool.pool.finalize();
    expect((await pool.pool.matured()).to.be.true);
    await lpVault.migrate(owner, pool.pool, pool.amm, stats);
  });
});
