// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../utils/IOwnable.sol";
import "../ITempusPool.sol";
import "../amm/ITempusAMM.sol";
import "../stats/Stats.sol";

interface ILPVaultV1 is IERC20Metadata, IOwnable {
    function yieldBearingToken() external view returns (IERC20);
    
    function pool() external view returns (ITempusPool);
    function amm() external view returns (ITempusAMM);
    function stats() external view returns (Stats);
    
    /// True if the vault is shut down. This mean depoists are disabled, but withdrawals
    
    function isShutdown() external view returns (bool);

    function previewDeposit(uint256 amount) external view returns (uint256 shares);
    function previewWithdraw(uint256 shares) external view returns (uint256 amount);

    /// Deposits `amount` of yield bearing tokens.
    /// @return shares The number of shares acquired.
    function deposit(uint256 amount, address recipient) external returns (uint256 shares);

    /// Withdraws `shares` of LPVault tokens.
    /// @return amount The number of yield bearing tokens acquired.
    function withdraw(uint256 shares, address recipient) external returns (uint256 amount);

    /// Migrates all funds from the current pool to the new pool.
    function migrate(
        ITempusPool newPool,
        ITempusAMM newAMM,
        Stats newStats
    ) external;

    function shutdown() external;

    function totalAssets() external view returns (uint256 tokenAmount);
}
