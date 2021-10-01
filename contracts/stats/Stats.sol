// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ITokenPairPriceFeed.sol";
import "./ChainlinkTokenPairPriceFeed/ChainlinkTokenPairPriceFeed.sol";
import "../ITempusPool.sol";
import "../math/Fixed256x18.sol";
import "../token/PoolShare.sol";
import "../amm/interfaces/ITempusAMM.sol";
import "../utils/AMMBalancesHelper.sol";

contract Stats is ITokenPairPriceFeed, ChainlinkTokenPairPriceFeed {
    using Fixed256x18 for uint256;
    using AMMBalancesHelper for uint256[];

    /// @param pool The TempusPool to fetch its TVL (total value locked)
    /// @return total value locked of a TempusPool (denominated in BackingTokens)
    function totalValueLockedInBackingTokens(ITempusPool pool) public view returns (uint256) {
        PoolShare principalShare = PoolShare(address(pool.principalShare()));
        PoolShare yieldShare = PoolShare(address(pool.yieldShare()));

        assert(principalShare.decimals() == 18 && yieldShare.decimals() == 18);

        uint256 pricePerPrincipalShare = pool.pricePerPrincipalShareStored();
        uint256 pricePerYieldShare = pool.pricePerYieldShareStored();

        return
            calculateTvlInBackingTokens(
                IERC20(address(principalShare)).totalSupply(),
                IERC20(address(yieldShare)).totalSupply(),
                pricePerPrincipalShare,
                pricePerYieldShare
            );
    }

    /// @param pool The TempusPool to fetch its TVL (total value locked)
    /// @param rateConversionData ENS nameHash of the ENS name of a Chainlink price aggregator (e.g. - the ENS nameHash of 'eth-usd.data.eth')
    /// @return total value locked of a TempusPool (denominated in the rate of the provided token pair)
    function totalValueLockedAtGivenRate(ITempusPool pool, bytes32 rateConversionData) external view returns (uint256) {
        uint256 tvlInBackingTokens = totalValueLockedInBackingTokens(pool);

        (uint256 rate, uint256 rateDenominator) = getRate(rateConversionData);
        return (tvlInBackingTokens * rate) / rateDenominator;
    }

    function calculateTvlInBackingTokens(
        uint256 totalSupplyTPS,
        uint256 totalSupplyTYS,
        uint256 pricePerPrincipalShare,
        uint256 pricePerYieldShare
    ) internal pure returns (uint256) {
        return totalSupplyTPS.mulf18(pricePerPrincipalShare) + totalSupplyTYS.mulf18(pricePerYieldShare);
    }

    /// Gets the estimated amount of Principals and Yields after a successful deposit
    /// @param pool Which tempus pool
    /// @param amount Amount of BackingTokens or YieldBearingTokens that would be deposited
    /// @param isBackingToken If true, @param amount is in BackingTokens, otherwise YieldBearingTokens
    /// @return Amount of Principals (TPS) and Yields (TYS) in Principal/YieldShare decimal precision.
    ///         TPS and TYS are minted in 1:1 ratio, hence a single return value.
    function estimatedMintedShares(
        ITempusPool pool,
        uint256 amount,
        bool isBackingToken
    ) public view returns (uint256) {
        return pool.estimatedMintedShares(amount, isBackingToken);
    }

    /// Gets the estimated amount of YieldBearingTokens or BackingTokens received when calling `redeemXXX()` functions
    /// @param pool Which tempus pool
    /// @param principals Amount of Principals (TPS)
    /// @param yields Amount of Yields (TYS)
    /// @param toBackingToken If true, redeem amount is estimated in BackingTokens instead of YieldBearingTokens
    /// @return Amount of YieldBearingTokens or BackingTokens in YBT/BT decimal precision
    function estimatedRedeem(
        ITempusPool pool,
        uint256 principals,
        uint256 yields,
        bool toBackingToken
    ) public view returns (uint256) {
        return pool.estimatedRedeem(principals, yields, toBackingToken);
    }

    /// Gets the estimated amount of Shares and Lp token amounts
    /// @param tempusAMM Tempus AMM to use to swap TYS for TPS
    /// @param amount Amount of BackingTokens or YieldBearingTokens that would be deposited
    /// @param isBackingToken If true, @param amount is in BackingTokens, otherwise YieldBearingTokens
    /// @return lpTokens Ampunt of LP tokens that user could recieve
    /// @return principals Amount of Principals that user could recieve in this action
    /// @return yields Amount of Yields that user could recieve in this action
    function estimatedDepositAndProvideLiquidity(
        ITempusAMM tempusAMM,
        uint256 amount,
        bool isBackingToken
    )
        public
        view
        returns (
            uint256 lpTokens,
            uint256 principals,
            uint256 yields
        )
    {
        ITempusPool pool = tempusAMM.tempusPool();
        uint256 shares = estimatedMintedShares(pool, amount, isBackingToken);

        (IERC20[] memory ammTokens, uint256[] memory ammBalances, ) = tempusAMM.getVault().getPoolTokens(
            tempusAMM.getPoolId()
        );
        uint256[] memory ammLiquidityProvisionAmounts = ammBalances.getLiquidityProvisionSharesAmounts(shares);

        lpTokens = tempusAMM.getExpectedLPTokensForTokensIn(ammLiquidityProvisionAmounts);
        (principals, yields) = (address(pool.principalShare()) == address(ammTokens[0]))
            ? (shares - ammLiquidityProvisionAmounts[0], shares - ammLiquidityProvisionAmounts[1])
            : (shares - ammLiquidityProvisionAmounts[1], shares - ammLiquidityProvisionAmounts[0]);
    }

    /// Gets the estimated amount of Shares and Lp token amounts
    /// @param tempusAMM Tempus AMM to use to swap TYS for TPS
    /// @param amount Amount of BackingTokens or YieldBearingTokens that would be deposited
    /// @param isBackingToken If true, @param amount is in BackingTokens, otherwise YieldBearingTokens
    /// @return principals Amount of Principals that user could recieve in this action
    function estimatedDepositAndFix(
        ITempusAMM tempusAMM,
        uint256 amount,
        bool isBackingToken
    ) public view returns (uint256 principals) {
        principals = estimatedMintedShares(tempusAMM.tempusPool(), amount, isBackingToken);
        principals += tempusAMM.getExpectedReturnGivenIn(principals, true);
    }

    /// @dev Get estimated amount of Backing or Yield bearing tokens for exiting pool and redeeming shares
    /// @notice This queries at certain block, actual results can differ as underlying pool state can change
    /// @param tempusAMM Tempus AMM to exit LP tokens from
    /// @param lpTokens Amount of LP tokens to use to query exit
    /// @param principals Amount of principals to query redeem
    /// @param yields Amount of yields to query redeem
    function estimateExitAndRedeem(
        ITempusAMM tempusAMM,
        uint256 lpTokens,
        uint256 principals,
        uint256 yields,
        bool toBackingToken
    ) public view returns (uint256) {
        (uint256 principalsFromLP, uint256 yieldsFromLp) = tempusAMM.getExpectedTokensOutGivenBPTIn(lpTokens);
        return
            estimatedRedeem(
                tempusAMM.tempusPool(),
                principalsFromLP + principals,
                yieldsFromLp + yields,
                toBackingToken
            );
    }
}
