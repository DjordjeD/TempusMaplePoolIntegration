// SPDX-License-Identifier: CC-0
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IEIP4626 is IERC20, IERC20Metadata {
    function deposit(address to, uint256 value) external returns (uint256 shares);

    function mint(address to, uint256 shares) external returns (uint256 value);

    function withdraw(
        address from,
        address to,
        uint256 value
    ) external returns (uint256 shares);

    function redeem(
        address from,
        address to,
        uint256 shares
    ) external returns (uint256 value);

    function underlying() external view returns (address);

    function totalUnderlying() external view returns (uint256);

    function balanceOfUnderlying(address owner) external view returns (uint256);

    function exchangeRate() external view returns (uint256);

    function previewDeposit(uint256 underlyingAmount) external view returns (uint256 shareAmount);

    function previewMint(uint256 shareAmount) external view returns (uint256 underlyingAmount);

    function previewWithdraw(uint256 underlyingAmount) external view returns (uint256 shareAmount);

    function previewRedeem(uint256 shareAmount) external view returns (uint256 underlyingAmount);
}
