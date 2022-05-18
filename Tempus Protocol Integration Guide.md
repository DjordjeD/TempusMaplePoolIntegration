Tempus Protocol Integration Guide

1. Create an adapter for TempusPool
  This provides all the necessary conversions from `MyLending` protocol to TempusPool
  Naming Convention: `MyLendingTestPool` if target protocol name is `MyLending`
  Path: `contracts/pools/MyLendingTestPool.sol`
  Example: `contracts/pools/AaveTempusPool.sol`

2. Create a mock contract `MyLendingMock.sol` for the target protocol
  This will later be used for unit testing via `MyLendingTestPool.ts`
  Path: `contracts/mocks/mylending/MyLendingMock.sol`
  Example: `contracts/mocks/aave/AavePoolMock.sol`

3. Create a typescript wrapper `MyLendingMock.ts`
  This is needed for `MyLendingTestPool.ts` to be able to modify the mock contract
  Technically this step can be skipped if you integrate all of this in `MyLendingTestPool.ts`
  Path: `test/utils/MyLending.ts`
  Example: `test/utils/Aave.ts`

4. Add TestPool implementation `MyLendingTestPool.ts` to enable Unit Tests
  Path: `test/pool-utils/MyLendingTestPool.ts`
  Example: `test/pool-utils/AaveTestPool.ts`

5. Update TestPool initialization in `test/pool-utils/MultiPoolTestSuite.ts`
  `describeTestBody` is where TestPool instances are created

6. Update `TempusPool.ts` to support the new integration:
  - Add new PoolType: `PoolType.MyLending`
  - Add a deployment utility: `static async deployMyLending(...)`
  - Update `deploy()` to run the `MyLendingTempusPool` constructor, every adapter has its own
    constructor

7. Update Token information in `Config.ts`
  You must define exactly what types of tokens are supported in `MOCK_TOKENS`,
  these are used to generate full test suite for the Pool-Token pair.

8. Update test runner script `run_tests.sh`
  This is needed to run all tests in parallel, otherwise unit tests would take forever to run.
  - Append your adapter into `POOLS` variable:
    `POOLS="Aave Lido Compound Yearn Rari MyLending"`
  - Define which tokens the pool supports:
    `POOL_TOKENS["MyLending"]="DAI SHIB"`
  - If needed, update `VALID_TOKENS`
    `VALID_TOKENS="DAI USDC ETH SHIB all"`

9. Run the tests
  - You can add `test:mylending` rule in `package.json` to only run MyLending tests:
    `"test:mylending": "yarn build && bash run_tests.sh MyLending",`
  - Or only use a specific token:
    `"test:mylending": "yarn build && bash run_tests.sh MyLending SHIB",`

