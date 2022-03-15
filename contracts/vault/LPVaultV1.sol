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
import "../amm/interfaces/ITempusAMM.sol";
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

    uint8 internal immutable tokenDecimals;

    IERC20 public immutable yieldBearingToken;
    uint256 private immutable oneYBT;

    ITempusPool public pool;
    ITempusAMM public amm;
    // TODO: remove dependency on stats
    Stats public stats;

    constructor(
        ITempusPool _pool,
        ITempusAMM _amm,
        Stats _stats,
        string memory name,
        string memory symbol
    ) ERC20OwnerMintableToken(name, symbol) {
        require(isAppropriateAMM(_pool, _amm), "AMM is not for the correct Pool");
        pool = _pool;
        amm = _amm;
        stats = _stats;
        yieldBearingToken = IERC20(pool.yieldBearingToken());
        tokenDecimals = IERC20Metadata(address(yieldBearingToken)).decimals();
        oneYBT = 10**tokenDecimals;
    }

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
        require(!pool.matured(), "No active pool is present.");

        shares = previewDeposit(amount);
        require(shares != 0, "No shares have been minted");

        yieldBearingToken.safeTransferFrom(msg.sender, address(this), amount);
        ITempusController(pool.controller()).depositAndProvideLiquidity(amm, pool, amount, false);

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
        ITempusController controller = ITempusController(pool.controller());

        // Redeem all LP tokens
        uint256 maxLpTokensToRedeem = IERC20(address(amm)).balanceOf(address(this));
        if (maxLpTokensToRedeem > 0) {
            controller.exitTempusAMM(amm, pool, maxLpTokensToRedeem, 1, 1, false);
        }

        // Withdraw from the Pool
        uint256 principals = IERC20(address(pool.principalShare())).balanceOf(address(this));
        uint256 yields = IERC20(address(pool.yieldShare())).balanceOf(address(this));
        // Withdraw if any shares are left
        if ((principals | yields) > 0) {
            controller.redeemToYieldBearing(pool, principals, yields, address(this));
        }
    }

    /// @return true if the given _amm uses the shares of the given _pool
    function isAppropriateAMM(ITempusPool _pool, ITempusAMM _amm) private view returns (bool) {
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

        require(newPool.yieldBearingToken() == address(yieldBearingToken), "The YieldBearingToken must be the same");
        require(isAppropriateAMM(newPool, newAMM), "AMM is not for the correct Pool");
        // FIXME: validate newStats too

        // Withdraw from current pool
        exitPool();

        uint256 amount = yieldBearingToken.balanceOf(address(this));

        // Deposit all yield bearing tokens to new pool
        ITempusController(newPool.controller()).depositAndProvideLiquidity(newAMM, newPool, amount, false);

        // NOTE: at this point any leftover shares will be "lost"
        // FIXME: decide what to do with leftover lp/principal/yield shares
        pool = newPool;
        amm = newAMM;
        stats = newStats;
    }

    /// @return tokenAmount the current total balance in terms of YBT held by the vault
    function totalAssets() private view returns (uint256 tokenAmount) {
        uint256 lpTokens = IERC20(address(amm)).balanceOf(address(this));
        uint256 principals = IERC20(address(pool.principalShare())).balanceOf(address(this));
        uint256 yields = IERC20(address(pool.yieldShare())).balanceOf(address(this));

        // TODO: scale this down based on some percentage of the AMM holdings (as opposed to potentially total)

        // TODO: what is a good threshold value?
        (tokenAmount, , , , ) = stats.estimateExitAndRedeem(
            amm,
            pool,
            lpTokens,
            principals,
            yields,
            /*threshold*/
            0,
            false
        );

        // TODO: what do with stray tokens?
        // NOTE: this is also the code path making sure withdrawal works post-maturity
        tokenAmount += yieldBearingToken.balanceOf(address(this));
    }
}
