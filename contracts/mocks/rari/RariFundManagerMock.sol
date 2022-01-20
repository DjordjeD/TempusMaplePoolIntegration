// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./RariFundPriceConsumerMock.sol";
import "../../token/ERC20OwnerMintableToken.sol";
import "../../protocols/rari/IRariFundManager.sol";
import "../../protocols/rari/IRariFundPriceConsumer.sol";
import "../../math/Fixed256xVar.sol";

contract RariFundManagerMock is IRariFundManager {
    using Fixed256xVar for uint256;

    IERC20Metadata private immutable asset;

    IRariFundPriceConsumer public immutable override rariFundPriceConsumer;
    address public immutable override rariFundToken;
    // used for mocks, it will force-fail the next deposit or redeem
    bool public mockFailNextDepositOrRedeem;
    uint256 private _fundBalanceMultiplier = 1e18;
    uint256 private _backingTokensDeposited;
    uint256 private immutable _currencyIndex;

    constructor(
        IERC20Metadata _asset,
        uint256 initialRate,
        string memory _name,
        string memory _symbol
    ) {
        uint256 backingTokenIndex = type(uint256).max;
        string memory backingTokenSymbol = _asset.symbol();
        string[] memory acceptedSymbols = getAcceptedCurrencies();
        for (uint256 i = 0; i < acceptedSymbols.length; i++) {
            if (keccak256(bytes(backingTokenSymbol)) == keccak256(bytes(acceptedSymbols[i]))) {
                backingTokenIndex = i;
                break;
            }
        }

        require(backingTokenIndex != type(uint256).max, "backing token is not accepted by the rari pool mock");

        _currencyIndex = backingTokenIndex;
        asset = _asset;
        rariFundPriceConsumer = new RariFundPriceConsumerMock(3);
        rariFundToken = address(new ERC20OwnerMintableToken(_name, _symbol));

        setInterestRate(initialRate);
    }

    /// @dev Same order as here - https://github.com/Rari-Capital/rari-stable-pool-contracts/blob/386aa8811e7f12c2908066ae17af923758503739/contracts/RariFundManager.sol#L104
    function getAcceptedCurrencies() public pure override returns (string[] memory) {
        string[] memory acceptedCurrencies = new string[](3);
        acceptedCurrencies[0] = "DAI";
        acceptedCurrencies[1] = "USDC";
        acceptedCurrencies[2] = "USDT";

        return acceptedCurrencies;
    }

    function isValidCurrencyCode(string calldata currencyCode) internal pure returns (bool) {
        string[] memory currencies = getAcceptedCurrencies();
        for (uint256 i = 0; i < currencies.length; i++) {
            if (keccak256(bytes(currencies[i])) == keccak256(bytes(currencyCode))) {
                return true;
            }
        }
        return false;
    }

    function getFundBalance() public view override returns (uint256) {
        uint256 backingTokenToUsdRate = rariFundPriceConsumer.getCurrencyPricesInUsd()[_currencyIndex];

        /// setInterestRate works by manipulating _backingTokensDeposited & _fundBalanceMultiplier
        uint256 scaledFundBalance = (_backingTokensDeposited.mulfV(backingTokenToUsdRate, 10**asset.decimals()) *
            _fundBalanceMultiplier) / 1e18;

        uint256 unscaledDeposits = (asset.balanceOf(address(this)) - _backingTokensDeposited).mulfV(
            backingTokenToUsdRate,
            10**asset.decimals()
        );

        return scaledFundBalance + unscaledDeposits;
    }

    function getWithdrawalFeeRate() external pure override returns (uint256) {
        return 0;
    }

    /// @notice MOCK ONLY
    /// @dev Sets the current pricePerShare
    /// @param interestRate Asset liquidity index. Expressed in BackingToken decimals precision
    function setInterestRate(uint256 interestRate) public {
        uint256 rftTotalSupply = IERC20(rariFundToken).totalSupply();

        _fundBalanceMultiplier = interestRate;
        _backingTokensDeposited = asset.balanceOf(address(this));

        RariFundPriceConsumerMock(address(rariFundPriceConsumer)).setCurrencyPriceInUsd(
            _currencyIndex,
            (interestRate == 0 || rftTotalSupply == 0) ? interestRate : 1e18
        );
    }

    /// @notice MOCK ONLY
    function setFailNextDepositOrRedeem(bool fail) public {
        mockFailNextDepositOrRedeem = fail;
    }

    /// @notice based on - https://github.com/Rari-Capital/rari-stable-pool-contracts/blob/386aa8811e7f12c2908066ae17af923758503739/contracts/RariFundManager.sol#L572
    function deposit(string calldata currencyCode, uint256 amount) external override {
        if (mockFailNextDepositOrRedeem) {
            setFailNextDepositOrRedeem(false);
            revert("random mock failure from rari");
        }

        require(isValidCurrencyCode(currencyCode), "Unsupported currency");

        uint256 rftTotalSupply = IERC20(rariFundToken).totalSupply();
        uint256 fundBalanceUsd = getFundBalance();
        uint256 backingTokenToUsdRate = rariFundPriceConsumer.getCurrencyPricesInUsd()[_currencyIndex];
        uint256 amountUsd = amount.mulfV(backingTokenToUsdRate, 10**asset.decimals());

        uint256 rftAmount = (rftTotalSupply > 0 && fundBalanceUsd > 0)
            ? amountUsd.mulfV(rftTotalSupply, fundBalanceUsd)
            : amountUsd;

        require(asset.transferFrom(msg.sender, address(this), amount), "transfer failed");
        ERC20OwnerMintableToken(rariFundToken).mint(msg.sender, rftAmount);
    }

    /// @notice based on - https://github.com/Rari-Capital/rari-stable-pool-contracts/blob/386aa8811e7f12c2908066ae17af923758503739/contracts/RariFundManager.sol#L737
    function withdraw(string calldata currencyCode, uint256 amount) external override returns (uint256) {
        if (mockFailNextDepositOrRedeem) {
            setFailNextDepositOrRedeem(false);
            revert("random mock failure from rari");
        }

        require(isValidCurrencyCode(currencyCode), "Unsupported currency");

        uint256 backingTokenToUsdRate = rariFundPriceConsumer.getCurrencyPricesInUsd()[_currencyIndex];
        uint256 amountUsd = amount.mulfV(backingTokenToUsdRate, 10**asset.decimals()); /// scale to 1e18

        // Calculate RFT to burn
        uint256 rftBurnAmount = getRftBurnAmount(msg.sender, amountUsd);

        ERC20OwnerMintableToken(rariFundToken).burnFrom(msg.sender, rftBurnAmount);
        asset.transfer(msg.sender, amount);

        return amount;
    }

    /// @notice based on https://github.com/Rari-Capital/rari-stable-pool-contracts/blob/386aa8811e7f12c2908066ae17af923758503739/contracts/RariFundManager.sol#L630
    function getRftBurnAmount(address from, uint256 amountUsd) internal view returns (uint256) {
        uint256 rftTotalSupply = IERC20(rariFundToken).totalSupply();
        uint256 fundBalanceUsd = getFundBalance();
        require(fundBalanceUsd > 0, "Fund balance is zero.");
        uint256 rftAmount = amountUsd.mulfV(rftTotalSupply, fundBalanceUsd);
        require(
            rftAmount <= IERC20(rariFundToken).balanceOf(from),
            "Your RFT balance is too low for a withdrawal of this amount."
        );
        require(rftAmount > 0, "Withdrawal amount is so small that no RFT would be burned.");
        return rftAmount;
    }
}
