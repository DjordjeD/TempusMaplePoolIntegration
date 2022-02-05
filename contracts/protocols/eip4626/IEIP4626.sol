// SPDX-License-Identifier: CC-0
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IEIP4626 is IERC20, IERC20Metadata {
    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);

    event Withdraw(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);

    function asset() external view returns (address assetTokenAddress);

    function totalAssets() external view returns (uint256 totalAssetsControlled);

    function assetsPerShare() external view returns (uint256 assetsPerUnitShare);

    function assetsOf(address owner) external view returns (uint256 assets);

    function maxDeposit(address caller) external view returns (uint256 maxAssets);

    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function maxMint(address caller) external view returns (uint256 maxShares);

    function previewMint(uint256 shares) external view returns (uint256 assets);

    function mint(uint256 shares, address receiver) external returns (uint256 value);

    function maxWithdraw(address caller) external view returns (uint256 maxAssets);

    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    function maxRedeem(address caller) external view returns (uint256 maxShares);

    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);
}
