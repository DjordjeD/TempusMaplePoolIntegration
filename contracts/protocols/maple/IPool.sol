// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
/***
    @notice based on https://github.dev/maple-labs/maple-core
*/
interface IPool is IERC20, IERC20Metadata {

    /**
        @dev   Handles Liquidity Providers depositing of Liquidity Asset into the LiquidityLocker, minting PoolFDTs.
        @dev   It emits a `DepositDateUpdated` event.
        @dev   It emits a `BalanceUpdated` event.
        @dev   It emits a `Cooldown` event.
        Amount of Liquidity Asset to deposit.
    */
    function deposit(uint256) external;


    /**
        @dev   Handles Liquidity Providers withd
        +rawing of Liquidity Asset from the LiquidityLocker, burning PoolFDTs.
        @dev   It emits two `BalanceUpdated` event.
        Amount of Liquidity Asset to withdraw.
    */
    function withdraw(uint256) external;


    /**
        @dev    Returns the total amount of funds a given address is able to withdraw currently.
        @param  owner Address of FDT holder.
        @return A uint256 representing the available funds for a given account.
    */
    function withdrawableFundsOf(address owner) external view returns (uint256);


    function liquidityAsset() external view returns (IERC20);


}