// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../TempusPool.sol";
import "../protocols/eip4626/IEIP4626.sol";
import "../utils/UntrustedERC20.sol";
import "../math/Fixed256xVar.sol";

contract EIP4626TempusPool is TempusPool {
    using SafeERC20 for IERC20;
    using UntrustedERC20 for IERC20;
    using Fixed256xVar for uint256;

    IEIP4626 private immutable vault;
    bytes32 public constant override protocolName = "EIP4626";

    constructor(
        IEIP4626 _vault,
        address controller,
        uint256 maturity,
        uint256 estYield,
        TokenData memory principalsData,
        TokenData memory yieldsData,
        FeesConfig memory maxFeeSetup
    )
        TempusPool(
            address(_vault),
            _vault.underlying(),
            controller,
            maturity,
            _vault.exchangeRate(),
            10**(IERC20Metadata(_vault.underlying()).decimals()),
            estYield,
            principalsData,
            yieldsData,
            maxFeeSetup
        )
    {
        require(_vault.decimals() == IERC20Metadata(_vault.underlying()).decimals(), "Decimals precision mismatch");

        vault = _vault;
    }

    function depositToUnderlying(uint256 amount) internal override returns (uint256) {
        // ETH deposits are not accepted, because it is rejected in the controller
        assert(msg.value == 0);

        // Deposit to Yearn Vault
        IERC20(backingToken).safeIncreaseAllowance(address(vault), amount);

        uint256 preDepositBalance = IERC20(yieldBearingToken).balanceOf(address(this));
        vault.deposit(address(this), amount);
        uint256 postDepositBalance = IERC20(yieldBearingToken).balanceOf(address(this));

        return (postDepositBalance - preDepositBalance);
    }

    function withdrawFromUnderlyingProtocol(uint256 yieldBearingTokensAmount, address recipient)
        internal
        override
        returns (uint256 backingTokenAmount)
    {
        return vault.withdraw(address(this), recipient, yieldBearingTokensAmount);
    }

    /// @return Updated current Interest Rate with the same precision as the BackingToken
    function updateInterestRate() internal view override returns (uint256) {
        vault.previewDeposit(1); // This is called to trigger an exchange rate recalculation.
        return vault.exchangeRate();
    }

    /// @return Stored Interest Rate with the same precision as the BackingToken
    function currentInterestRate() public view override returns (uint256) {
        return vault.exchangeRate();
    }

    function numAssetsPerYieldToken(uint yieldTokens, uint rate) public view override returns (uint) {
        return yieldTokens.mulfV(rate, exchangeRateONE);
    }

    function numYieldTokensPerAsset(uint backingTokens, uint rate) public view override returns (uint) {
        return backingTokens.divfV(rate, exchangeRateONE);
    }

    /// @dev The rate precision always matches the BackingToken's precision
    function interestRateToSharePrice(uint interestRate) internal pure override returns (uint) {
        return interestRate;
    }
}
