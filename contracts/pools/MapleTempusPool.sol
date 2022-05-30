pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


import "../protocols/maple/IPool.sol";

import "../TempusPool.sol";

contract MapleTempusPool is TempusPool {
    using SafeERC20 for IERC20Metadata;
    using UntrustedERC20 for IERC20Metadata;

    IPool internal immutable maplePool;
    //bytes32 public constant override protocolName = "Maple";
    uint256 private immutable exchangeRateToBackingPrecision;
    /// @dev Error thrown when the `withdrawFromUnderlyingProtocol` method is called for Lido pool
    error MapleWithdrawNotSupported();
    
    constructor(
        IPool token,
        address controller,
        uint256 maturity,
        uint256 estYield,
        TokenData memory principalsData,
        TokenData memory yieldsData,
        FeesConfig memory maxFeeSetup
    )
        TempusPool(
            IERC20Metadata(address(token)),
            IERC20Metadata(address(token.liquidityAsset())),
            controller,
            maturity,
            1e12,
            1e18,
            estYield,
            principalsData,
            yieldsData,
            maxFeeSetup
        )
    {
        maplePool = token;
        //decimals precision
        IERC20Metadata backing = IERC20Metadata(address(maplePool.liquidityAsset()));
        uint8 underlyingDecimals = backing.decimals();
        if (underlyingDecimals > 18) {
            revert MoreThanMaximumExpectedDecimals(backing, underlyingDecimals, 18);
        }
        unchecked {
            exchangeRateToBackingPrecision = 10**(18 - underlyingDecimals);
        }
    }

    
    function depositToUnderlying(uint256 amountBT)
        internal
        override
        assertTransferBT(amountBT)
        returns (uint256 mintedYBT)
    {
        // ETH deposits are not accepted, because it is rejected in the controller
        assert(msg.value == amountBT);

        uint256 ybtBefore = balanceOfYBT();
        maplePool.deposit(amountBT);

        mintedYBT = balanceOfYBT() - ybtBefore;
    }

    function withdrawFromUnderlyingProtocol(uint256 yieldBearingTokensAmount, address recipient)
        internal
        override
        assertTransferYBT(yieldBearingTokensAmount, 1)
        returns (uint256)
    {
        revert MapleWithdrawNotSupported();
        return 0;
    }

    /// @return Updated current Interest Rate as an 1e18 decimal
    function updateInterestRate() public view override returns (uint256) {
        // convert from RAY 1e27 to WAD 1e18 decimal
        return maplePool.withdrawableFundsOf(controller)/balanceOfYBT() + 1;
    }

    /// @return Stored Interest Rate as an 1e18 decimal
    function currentInterestRate() public view override returns (uint256) {
        return maplePool.withdrawableFundsOf(controller)/balanceOfYBT() + 1;
    }

    /// NOTE: Maple PoolFDT is pegged 1:1 with backing token
    function numAssetsPerYieldToken(uint256 yieldTokens, uint256) public pure override returns (uint256) {
        return yieldTokens;
    }

    /// NOTE: Maple PoolFDT is pegged 1:1 with backing token
    function numYieldTokensPerAsset(uint256 backingTokens, uint256) public pure override returns (uint256) {
        return backingTokens;
    }

    function interestRateToSharePrice(uint256 interestRate) internal view override returns (uint256) {
        return interestRate / exchangeRateToBackingPrecision;
    }
}