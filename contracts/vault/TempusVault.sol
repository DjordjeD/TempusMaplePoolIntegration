// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../amm/interfaces/ITempusAMM.sol";
import "../token/IPoolShare.sol";
import "../utils/Ownable.sol";
import "../ITempusPool.sol";

contract TempusVault is Ownable {
    mapping(address => bool) public whitelistedAmms;
    event AmmRegistered(
        address indexed amm
    );
    event AmmUnregistered(
        address indexed amm
    );
    constructor() {}

    function registerAmm(address amm) external onlyOwner {
        whitelistedAmms[amm] = true;
    }
    function unregisterAmm(address amm) external onlyOwner {
        whitelistedAmms[amm] = true;
    }

    /// TODO:
    /// 1. allow anyone to call rebalance or impose auth?
    /// 2. impose transfer limits (unless pool has matured)
    /// 3. implement min transfer limits (if only a tiny amount needs to be transferred
    ///             between pools to reach a balanced state, just don't do it.)
    /// 4. whitelist amms
    //// 5. Calculating liquidity share of given pool --- ( 1 - ( POOL_AMP / TOTAL_POOLS_AMP_SUM ) )
    function rebalance(ITempusAMM[] calldata amms) public onlyOwner {
        require(amms.length > 0); /// TODO: IMPORTANT error msg
        require(amms.length <= 4); /// TODO: IMPORTANT error msg

        uint256[] memory ammsLiquidity = new uint256[](amms.length);
        uint256[] memory ammsAmplificationParameters = new uint256[](amms.length);
        uint256 totalAmp = 0;
        for (uint256 i = 0; i < amms.length; i++) {
            ITempusAMM amm = amms[i];
            ITempusPool pool = amm.tempusPool();
            (uint256 ampParameter, , ) = amm.getAmplificationParameter();
            totalAmp += ampParameter;
            ammsAmplificationParameters[i] = ampParameter;
            ammsLiquidity[i] = calculateAmmValue(amms[i]);
            /// TODO: IMPORTANT verify all backingTokens match
        }
    }

    function calculateAmmValue(ITempusAMM amm) private view returns (uint256) {
        ITempusPool pool = amm.tempusPool();

        /// TODO: IMPORTANT maybe use the Balancer Vault to query these
        uint256 principalBalance = IERC20(address(pool.principalShare())).balanceOf(address(amm));
        uint256 yieldBalance = IERC20(address(pool.yieldShare())).balanceOf(address(amm));

        uint256 ybtValue = pool.estimatedRedeem(principalBalance, yieldBalance, false);
        return ybtValue;
    }
}
