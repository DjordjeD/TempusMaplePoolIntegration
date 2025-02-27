// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./token/IPoolShare.sol";
import "./utils/IOwnable.sol";

/// Setting and transferring of fees are restricted to the owner.
interface ITempusFees is IOwnable {
    /// The fees are in terms of yield bearing token (YBT).
    struct FeesConfig {
        uint256 depositPercent;
        uint256 earlyRedeemPercent;
        uint256 matureRedeemPercent;
    }

    /// Returns the current fee configuration.
    function getFeesConfig() external view returns (FeesConfig memory);

    /// Replace the current fee configuration with a new one.
    /// By default all the fees are expected to be set to zero.
    /// @notice This function can only be called by the owner.
    function setFeesConfig(FeesConfig calldata newFeesConfig) external;

    /// @return Maximum possible fee percentage that can be set for deposit
    function maxDepositFee() external view returns (uint256);

    /// @return Maximum possible fee percentage that can be set for early redeem
    function maxEarlyRedeemFee() external view returns (uint256);

    /// @return Maximum possible fee percentage that can be set for mature redeem
    function maxMatureRedeemFee() external view returns (uint256);

    /// Accumulated fees available for withdrawal.
    function totalFees() external view returns (uint256);

    /// Transfers accumulated Yield Bearing Token (YBT) fees
    /// from this pool contract to `recipient`.
    /// @param recipient Address which will receive the specified amount of YBT
    /// @notice This function can only be called by the owner.
    function transferFees(address recipient) external;
}

/// All state changing operations are restricted to the controller.
interface ITempusPool is ITempusFees, IERC165 {
    /// @dev Error thrown when the given's pool maturity time has already passed
    /// @param maturity The maturity timestamp
    /// @param startTime The pool start timestamp
    error MaturityTimeBeforeStartTime(uint256 maturity, uint256 startTime);

    /// @dev Error thrown when the address of the controller is the zero address
    error ZeroAddressController();

    /// @dev Error thrown when the interest rate is zero
    error ZeroInterestRate();

    /// @dev Error thrown when the estimated final yield is zero
    error ZeroEstimatedFinalYield();

    /// @dev Error thrown when the address of the yield bearing token is the zero address
    error ZeroAddressYieldBearingToken();

    /// @dev Error thrown when the method call does not come from the Tempus controller
    /// @param deniedCaller The address of the denied caller
    error OnlyControllerAuthorized(address deniedCaller);

    /// @dev Error thrown when a fee percentage is bigger than the maximum
    /// @param actionType The type of action
    /// @param feePercent The fee percent given
    /// @param maximumFeePercent The maximum fee percent allowed
    error FeePercentageTooBig(bytes32 actionType, uint256 feePercent, uint256 maximumFeePercent);

    /// @dev Error thrown when the pool has already matured
    /// @param tempusPool The address of the pool that has already matured
    error PoolAlreadyMatured(ITempusPool tempusPool);

    /// @dev Error thrown when the yield is negative
    error NegativeYield();

    /// @dev Error thrown when the principal token balance is insufficient
    /// @param principalTokenBalance The principal token balance
    /// @param expectedPrincipalTokenAmount The expected principal token amount
    error InsufficientPrincipalTokenBalance(uint256 principalTokenBalance, uint256 expectedPrincipalTokenAmount);

    /// @dev Error thrown when the yield token balance is insufficient
    /// @param yieldTokenBalance The yield token balance
    /// @param expectedYieldTokenAmount The expected yield token amount
    error InsufficientYieldTokenBalance(uint256 yieldTokenBalance, uint256 expectedYieldTokenAmount);

    /// @dev Error thrown when trying to exit pool before maturity but pricipal and yield token amounts are not equal
    /// @param principalTokenAmount The amount of principal tokens
    /// @param yieldTokenAmount The amount of yield tokens
    error NotEqualPrincipalAndYieldTokenAmounts(uint256 principalTokenAmount, uint256 yieldTokenAmount);

    /// @dev Error thrown when the expected decimals of a token are more than the maximum expected decimals
    /// @param token The address of the token
    /// @param maximumExpectedDecimals The maximum expected decimals
    /// @param actualDecimals The actual decimals
    error MoreThanMaximumExpectedDecimals(IERC20 token, uint256 maximumExpectedDecimals, uint256 actualDecimals);

    /// @dev Error thrown when the given token is not a valid one in the pool's context
    /// @param token The address of the given token
    error InvalidBackingToken(IERC20 token);

    /// @dev Error thrown when the expected decimals of a token do not match the actual ones
    /// @param token The address of the token
    /// @param expectedDecimals The expected decimals
    /// @param actualDecimals The actual decimals
    error DecimalsPrecisionMismatch(IERC20 token, uint256 expectedDecimals, uint256 actualDecimals);

    /// @return The name of underlying protocol, for example "Aave" for Aave protocol
    function protocolName() external view returns (bytes32);

    /// This token will be used as a token that user can deposit to mint same amounts
    /// of principal and interest shares.
    /// @return The underlying yield bearing token.
    function yieldBearingToken() external view returns (IERC20Metadata);

    /// This is the address of the actual backing asset token
    /// in the case of ETH, this address will be 0
    /// @return Address of the Backing Token
    function backingToken() external view returns (IERC20Metadata);

    /// @return uint256 value of one backing token, in case of 18 decimals 1e18
    function backingTokenONE() external view returns (uint256);

    /// @return This TempusPool's Tempus Principal Share (TPS)
    function principalShare() external view returns (IPoolShare);

    /// @return This TempusPool's Tempus Yield Share (TYS)
    function yieldShare() external view returns (IPoolShare);

    /// @return The TempusController address that is authorized to perform restricted actions
    function controller() external view returns (address);

    /// @return Start time of the pool.
    function startTime() external view returns (uint256);

    /// @return Maturity time of the pool.
    function maturityTime() external view returns (uint256);

    /// @return Time of exceptional halting of the pool.
    /// In case the pool is still in operation, this must return type(uint256).max.
    function exceptionalHaltTime() external view returns (uint256);

    /// @return The maximum allowed time (in seconds) to pass with negative yield.
    function maximumNegativeYieldDuration() external view returns (uint256);

    /// @return True if maturity has been reached and the pool was finalized.
    ///         This also includes the case when maturity was triggered due to
    ///         exceptional conditions (negative yield periods).
    function matured() external view returns (bool);

    /// Finalizes the pool. This can only happen on or after `maturityTime`.
    /// Once finalized depositing is not possible anymore, and the behaviour
    /// redemption will change.
    ///
    /// Can be called by anyone and can be called multiple times.
    function finalize() external;

    /// Yield bearing tokens deposit hook.
    /// @notice Deposit will fail if maturity has been reached.
    /// @notice This function can only be called by TempusController
    /// @notice This function assumes funds were already transferred to the TempusPool from the TempusController
    /// @param yieldTokenAmount Amount of yield bearing tokens to deposit in YieldToken decimal precision
    /// @param recipient Address which will receive Tempus Principal Shares (TPS) and Tempus Yield Shares (TYS)
    /// @return mintedShares Amount of TPS and TYS minted to `recipient`
    /// @return depositedBT The YBT value deposited, denominated as Backing Tokens
    /// @return fee The fee which was deducted (in terms of YBT)
    /// @return rate The interest rate at the time of the deposit
    function onDepositYieldBearing(uint256 yieldTokenAmount, address recipient)
        external
        returns (
            uint256 mintedShares,
            uint256 depositedBT,
            uint256 fee,
            uint256 rate
        );

    /// Backing tokens deposit hook.
    /// @notice Deposit will fail if maturity has been reached.
    /// @notice This function can only be called by TempusController
    /// @notice This function assumes funds were already transferred to the TempusPool from the TempusController
    /// @param backingTokenAmount amount of Backing Tokens to be deposited to underlying protocol
    ///         in BackingToken decimal precision
    /// @param recipient Address which will receive Tempus Principal Shares (TPS) and Tempus Yield Shares (TYS)
    /// @return mintedShares Amount of TPS and TYS minted to `recipient`
    /// @return depositedYBT The BT value deposited, denominated as Yield Bearing Tokens
    /// @return fee The fee which was deducted (in terms of YBT)
    /// @return rate The interest rate at the time of the deposit
    function onDepositBacking(uint256 backingTokenAmount, address recipient)
        external
        payable
        returns (
            uint256 mintedShares,
            uint256 depositedYBT,
            uint256 fee,
            uint256 rate
        );

    /// Redeems yield bearing tokens from this TempusPool
    ///      msg.sender will receive the YBT
    ///      NOTE #1 Before maturity, principalAmount must equal to yieldAmount.
    ///      NOTE #2 This function can only be called by TempusController
    /// @param from Address to redeem its Tempus Shares
    /// @param principalAmount Amount of Tempus Principal Shares (TPS)
    ///         to redeem for YBT in PrincipalShare decimal precision
    /// @param yieldAmount Amount of Tempus Yield Shares (TYS) to redeem for YBT in YieldShare decimal precision
    /// @param recipient Address to which redeemed YBT will be sent
    /// @return redeemableYieldTokens Amount of Yield Bearing Tokens redeemed to `recipient`
    /// @return fee The fee which was deducted (in terms of YBT)
    /// @return rate The interest rate at the time of the redemption
    function redeem(
        address from,
        uint256 principalAmount,
        uint256 yieldAmount,
        address recipient
    )
        external
        returns (
            uint256 redeemableYieldTokens,
            uint256 fee,
            uint256 rate
        );

    /// Redeems TPS+TYS held by msg.sender into backing tokens
    ///      `msg.sender` must approve TPS and TYS amounts to this TempusPool.
    ///      `msg.sender` will receive the backing tokens
    ///      NOTE #1 Before maturity, principalAmount must equal to yieldAmount.
    ///      NOTE #2 This function can only be called by TempusController
    /// @param from Address to redeem its Tempus Shares
    /// @param principalAmount Amount of Tempus Principal Shares (TPS) to redeem in PrincipalShare decimal precision
    /// @param yieldAmount Amount of Tempus Yield Shares (TYS) to redeem in YieldShare decimal precision
    /// @param recipient Address to which redeemed BT will be sent
    /// @return redeemableYieldTokens Amount of Backing Tokens redeemed to `recipient`, denominated in YBT
    /// @return redeemableBackingTokens Amount of Backing Tokens redeemed to `recipient`
    /// @return fee The fee which was deducted (in terms of YBT)
    /// @return rate The interest rate at the time of the redemption
    function redeemToBacking(
        address from,
        uint256 principalAmount,
        uint256 yieldAmount,
        address recipient
    )
        external
        payable
        returns (
            uint256 redeemableYieldTokens,
            uint256 redeemableBackingTokens,
            uint256 fee,
            uint256 rate
        );

    /// @dev Gets the estimated amount of Principals and Yields after a successful deposit
    /// @param amount Amount of BackingTokens or YieldBearingTokens that would be deposited
    /// @param isBackingToken If true, @param amount is in BackingTokens, otherwise YieldBearingTokens
    /// @return Amount of Principals (TPS) and Yields (TYS) in Principal/YieldShare decimal precision
    ///         TPS and TYS are minted in 1:1 ratio, hence a single return value.
    function estimatedMintedShares(uint256 amount, bool isBackingToken) external view returns (uint256);

    /// @dev Gets the estimated amount of YieldBearingTokens or BackingTokens received
    ///     when calling `redeemXXX()` functions
    /// @param principals Amount of Principals (TPS) in PrincipalShare decimal precision
    /// @param yields Amount of Yields (TYS) in YieldShare decimal precision
    /// @param toBackingToken If true, redeem amount is estimated in BackingTokens instead of YieldBearingTokens
    /// @return Amount of YieldBearingTokens or BackingTokens in YBT/BT decimal precision
    function estimatedRedeem(
        uint256 principals,
        uint256 yields,
        bool toBackingToken
    ) external view returns (uint256);

    /// @dev Gets the number of Principals and Yields for exact YBT/BT amount out
    /// This function can be called only before maturity
    /// @param amountOut Amount of BackingTokens or YieldBearingTokens to be withdrawn
    /// @param isBackingToken If true, @param amountOut is in BackingTokens, otherwise YieldBearingTokens
    /// @return Amount of Principals (TPS) and Yields (TYS) in Principal/YieldShare decimal precision
    ///         TPS and TYS are redeemed in 1:1 ratio before maturity, hence a single return value.
    function getSharesAmountForExactTokensOut(uint256 amountOut, bool isBackingToken) external view returns (uint256);

    /// @dev This updates the underlying pool's interest rate
    ///      It is done first thing before deposit/redeem to avoid arbitrage
    ///      It is available to call publically to periodically update interest rates in cases of low volume
    /// @return Updated current Interest Rate, decimal precision depends on specific TempusPool implementation
    function updateInterestRate() external returns (uint256);

    /// @dev This returns the stored Interest Rate of the YBT (Yield Bearing Token) pool
    ///      it is safe to call this after updateInterestRate() was called
    /// @return Stored Interest Rate, decimal precision depends on specific TempusPool implementation
    function currentInterestRate() external view returns (uint256);

    /// @return Initial interest rate of the underlying pool,
    ///         decimal precision depends on specific TempusPool implementation
    function initialInterestRate() external view returns (uint256);

    /// @return Interest rate at maturity of the underlying pool (or 0 if maturity not reached yet)
    ///         decimal precision depends on specific TempusPool implementation
    function maturityInterestRate() external view returns (uint256);

    /// @return Rate of one Tempus Yield Share expressed in Asset Tokens
    function pricePerYieldShare() external returns (uint256);

    /// @return Rate of one Tempus Principal Share expressed in Asset Tokens
    function pricePerPrincipalShare() external returns (uint256);

    /// Calculated with stored interest rates
    /// @return Rate of one Tempus Yield Share expressed in Asset Tokens,
    function pricePerYieldShareStored() external view returns (uint256);

    /// Calculated with stored interest rates
    /// @return Rate of one Tempus Principal Share expressed in Asset Tokens
    function pricePerPrincipalShareStored() external view returns (uint256);

    /// @dev This returns actual Backing Token amount for amount of YBT (Yield Bearing Tokens)
    ///      For example, in case of Aave and Lido the result is 1:1,
    ///      and for compound is `yieldTokens * currentInterestRate`
    /// @param yieldTokens Amount of YBT in YBT decimal precision
    /// @param interestRate The current interest rate
    /// @return Amount of Backing Tokens for specified @param yieldTokens
    function numAssetsPerYieldToken(uint256 yieldTokens, uint256 interestRate) external view returns (uint256);

    /// @dev This returns amount of YBT (Yield Bearing Tokens) that can be converted
    ///      from @param backingTokens Backing Tokens
    /// @param backingTokens Amount of Backing Tokens in BT decimal precision
    /// @param interestRate The current interest rate
    /// @return Amount of YBT for specified @param backingTokens
    function numYieldTokensPerAsset(uint256 backingTokens, uint256 interestRate) external view returns (uint256);
}
