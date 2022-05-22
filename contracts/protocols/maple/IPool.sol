// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../token/interfaces/IPoolFDT.sol";


/***
    @notice based on https://github.dev/maple-labs/maple-core
*/
interface IPool is IPoolFDT {

    /**
        @dev   Handles Liquidity Providers depositing of Liquidity Asset into the LiquidityLocker, minting PoolFDTs.
        @dev   It emits a `DepositDateUpdated` event.
        @dev   It emits a `BalanceUpdated` event.
        @dev   It emits a `Cooldown` event.
        @param amt Amount of Liquidity Asset to deposit.
    */
    function deposit(uint256) external;


    /**
        @dev   Handles Liquidity Providers withd
        +rawing of Liquidity Asset from the LiquidityLocker, burning PoolFDTs.
        @dev   It emits two `BalanceUpdated` event.
        @param amt Amount of Liquidity Asset to withdraw.
    */
    function withdraw(uint256) external;

}