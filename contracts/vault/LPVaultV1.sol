// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../math/Fixed256xVar.sol";
import "../token/ERC20OwnerMintableToken.sol";
import "../utils/Ownable.sol";
import "../utils/UntrustedERC20.sol";
import "../ITempusController.sol";
import "../ITempusPool.sol";
import "../amm/ITempusAMM.sol";
import "../stats/Stats.sol";

/// This LP Vault follows a very simple strategy.
/// TODO: make this EIP4626 compatible
///
/// Support needed from AMM:
/// 1. Calculate current holdings in terms of YBT
/// 2. Buy holdings in exchange of given YBT
///    - How much lpVaultShare to give from given YBT?
///    - This is solved by depositAndProvideLiquidity
/// 3. Sell holdings to get required amount of YBT
///    - How much principal/yield/LP (and how much lpVaultShare that represents) to sell for given YBT?
contract LPVaultV1 is ERC20OwnerMintableToken, Ownable {
    using SafeERC20 for IERC20;
    using UntrustedERC20 for IERC20;
    using Fixed256xVar for uint256;

    // The decimals are the same as yield bearing token.
    uint8 internal immutable tokenDecimals;

    IERC20 public immutable yieldBearingToken;
    uint256 private immutable oneYBT; // also equals to oneVaultShare
    uint256 private immutable onePoolShare;
    uint256 private immutable oneLP;

    ITempusPool public pool;
    ITempusAMM public amm;
    // TODO: remove dependency on stats
    Stats public stats;

    bool public isShutdown;

    // NOTE about decimals
    // BT -- variable
    // YBT -- variable
    // poolShares -- equals BT
    // LP -- fixed 18
    // vaultShare -- equals YBT
    constructor(
        ITempusPool _pool,
        ITempusAMM _amm,
        Stats _stats,
        string memory name,
        string memory symbol
    ) ERC20OwnerMintableToken(name, symbol) {
        require(isTempusPoolAMM(_pool, _amm), "AMM is not for the correct Pool");
        pool = _pool;
        amm = _amm;
        stats = _stats;
        yieldBearingToken = IERC20(pool.yieldBearingToken());
        tokenDecimals = IERC20Metadata(address(yieldBearingToken)).decimals();

        oneYBT = 10**tokenDecimals;
        assert(
            IERC20Metadata(address(pool.principalShare())).decimals() ==
                IERC20Metadata(address(pool.yieldShare())).decimals()
        );
        onePoolShare = 10**IERC20Metadata(address(pool.principalShare())).decimals();
        // NOTE: this should be 18 decimals in every case, but asserting has the same cost
        oneLP = 10**IERC20Metadata(address(amm)).decimals();

        // Unlimited approval.
//        yieldBearingToken.safeApprove(pool.controller(), type(uint256).max);
        yieldBearingToken.approve(pool.controller(), type(uint256).max);
        amm.approve(pool.controller(), type(uint256).max);
    }

    // This mirrors the decimals of the underlying yield bearing token.
    function decimals() public view virtual override returns (uint8) {
        return tokenDecimals;
    }

    function previewDeposit(uint256 amount) public view returns (uint256 shares) {
        uint256 supply = totalSupply();
        // TODO: rounding
        return (supply == 0) ? amount : amount.mulfV(supply, totalAssets());
    }

    function previewWithdraw(uint256 shares) public view returns (uint256 amount) {
        uint256 supply = totalSupply();
        // TODO: rounding
        return (supply == 0) ? shares : shares.mulfV(totalAssets(), supply);
    }

    /// Deposits `amount` of yield bearing tokens.
    /// @return shares The number of shares acquired.
    function deposit(uint256 amount, address recipient) external returns (uint256 shares) {
        // Quick exit path.
        require(!isShutdown, "Vault is shut down.");
        //        require(!pool.matured(), "No active pool is present.");

        shares = previewDeposit(amount);
        require(shares != 0, "No shares have been minted");

        yieldBearingToken.safeTransferFrom(msg.sender, address(this), amount);
        if (!pool.matured()) {
            ITempusController(pool.controller()).depositAndProvideLiquidity(amm, pool, amount, false);
        }

        _mint(recipient, shares);
    }

    /// Withdraws `shares` of LPVault tokens.
    /// @return amount The number of yield bearing tokens acquired.
    function withdraw(uint256 shares, address recipient) external returns (uint256 amount) {
        if (pool.matured()) {
            // Upon maturity withdraw all existing liquidity.
            // Doing this prior to totalAssets for less calculation risk.
            exitPool();
        }

        amount = previewWithdraw(shares);
        require(amount != 0, "No shares would be burned");

        _burn(msg.sender, shares);

        if (pool.matured()) {
            yieldBearingToken.safeTransfer(recipient, amount);
        } else {
            uint256 requiredShares = pool.getSharesAmountForExactTokensOut(amount, false);

            (
                uint256 principals,
                uint256 yields,
                uint256 principalsStaked,
                uint256 yieldsStaked,
                uint256 maxLpTokensToRedeem
            ) = calculateWithdrawalShareSplit(requiredShares);

            ITempusController(pool.controller()).exitAmmGivenAmountsOutAndEarlyRedeem(
                amm,
                pool,
                principals,
                yields,
                principalsStaked,
                yieldsStaked,
                maxLpTokensToRedeem,
                false
            );
        }
    }

    // FIXME: move to some generic helper file
    function min(uint256 a, uint256 b) private pure returns (uint256 c) {
        c = (a < b) ? a : b;
    }

    /// This function calculates the "optimal" share split for withdrawals. It prefers
    /// unstaked principals/yields for efficiency.
    function calculateWithdrawalShareSplit(uint256 requiredShares)
        private
        view
        returns (
            uint256 principals,
            uint256 yields,
            uint256 principalsStaked,
            uint256 yieldsStaked,
            uint256 lpTokens
        )
    {
        (principalsStaked, yieldsStaked) = amm.compositionBalanceOf(address(this));
        lpTokens = IERC20(address(amm)).balanceOf(address(this));
        principals = IERC20(address(pool.principalShare())).balanceOf(address(this));
        yields = IERC20(address(pool.yieldShare())).balanceOf(address(this));

        if (requiredShares > principals) {
            principalsStaked = min(requiredShares - principals, principalsStaked);
        } else {
            principals = requiredShares;
            principalsStaked = 0;
        }

        if (requiredShares > yields) {
            yieldsStaked = min(requiredShares - yields, yieldsStaked);
        } else {
            yields = requiredShares;
            yieldsStaked = 0;
        }

        require((principals + principalsStaked) >= requiredShares, "Not enough principals.");
        require((yields + yieldsStaked) >= requiredShares, "Not enough yields.");

        // FIXME: scale lpTokens with the ratio of principals/yieldsStaked redeemed here
    }

    /// Completely exit the AMM+Pool.
    function exitPool() private {
        // Redeem all LP tokens
        uint256 principals = IERC20(address(pool.principalShare())).balanceOf(address(this));
        uint256 yields = IERC20(address(pool.yieldShare())).balanceOf(address(this));
        uint256 maxLpTokensToRedeem = IERC20(address(amm)).balanceOf(address(this));
        if (maxLpTokensToRedeem > 0) {
            amm.exitGivenLpIn(maxLpTokensToRedeem, principals, yields, address(this));
        }

        // Withdraw from the Pool
        principals = IERC20(address(pool.principalShare())).balanceOf(address(this));
        yields = IERC20(address(pool.yieldShare())).balanceOf(address(this));
        // Withdraw if any shares are left
        if ((principals | yields) > 0) {
            ITempusController controller = ITempusController(pool.controller());
            controller.redeemToYieldBearing(pool, principals, yields, address(this));
        }
    }

    /// @return true if given TempusAMM uses shares of the given TempusPool.
    function isTempusPoolAMM(ITempusPool _pool, ITempusAMM _amm) private view returns (bool) {
        IPoolShare token0 = _amm.token0();
        IPoolShare token1 = _amm.token1();
        IPoolShare principalShare = _pool.principalShare();
        IPoolShare yieldShare = _pool.yieldShare();
        return (token0 == principalShare && token1 == yieldShare) || (token0 == yieldShare && token1 == principalShare);
    }

    /// Migrates all funds from the current pool to the new pool.
    function migrate(
        ITempusPool newPool,
        ITempusAMM newAMM,
        Stats newStats
    ) external onlyOwner {
        // Only allow migration after maturity to avoid withdrawal risks (loss and/or lockup due to liquidity) from pool.
        require(pool.matured(), "Current Pool has not matured yet");

        require(
            address(newPool.yieldBearingToken()) == address(yieldBearingToken),
            "The YieldBearingToken must be the same"
        );
        require(isTempusPoolAMM(newPool, newAMM), "AMM is not for the correct Pool");
        // FIXME: validate newStats too

        // Withdraw from current pool
        exitPool();

        uint256 amount = yieldBearingToken.balanceOf(address(this));

        // Deposit all yield bearing tokens to new pool
        // Unlimited approval.
//        yieldBearingToken.safeApprove(newPool.controller(), type(uint256).max);
        yieldBearingToken.approve(newPool.controller(), type(uint256).max);
        newAMM.approve(newPool.controller(), type(uint256).max);
        if (amount > 0) {
            ITempusController(newPool.controller()).depositAndProvideLiquidity(newAMM, newPool, amount, false);
        }

        // NOTE: at this point any leftover shares will be "lost"
        // FIXME: decide what to do with leftover lp/principal/yield shares
        // Remove unlimited approval
        //yieldBearingToken.safeApprove(pool.controller(), 0);
        amm.approve(pool.controller(), 0);
        pool = newPool;
        amm = newAMM;
        stats = newStats;
    }

    function shutdown() external onlyOwner {
        // exit pools

        isShutdown = true;
    }

    function totalAssets() public view returns (uint256 tokenAmount) {
        return pricePerShare().mulfV(totalSupply(), oneYBT);
    }

    /// Price per share in YBT.
    function pricePerShare() private view returns (uint256 rate) {
        uint256 ybtBalance = yieldBearingToken.balanceOf(address(this));
        uint256 lpTokens = IERC20(address(amm)).balanceOf(address(this));
        uint256 principals = IERC20(address(pool.principalShare())).balanceOf(address(this));
        uint256 yields = IERC20(address(pool.yieldShare())).balanceOf(address(this));

        uint256 supply = totalSupply();
        require(supply != 0, "PricePerShare for 0 supply is not allowed");

        (rate, , , , ) = stats.estimateExitAndRedeem(
            amm,
            pool,
            lpTokens.divfV(supply, oneYBT),
            principals.divfV(supply, oneYBT),
            yields.divfV(supply, oneYBT),
            /*threshold*/
            10 * onePoolShare,
            false
        );
        rate += ybtBalance.divfV(supply, oneYBT);
    }
}
