// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "./IERC20Vesting.sol";

contract ERC20Vesting is IERC20Vesting {
    address public immutable override wallet;
    IERC20 public immutable override token;
    mapping(address => VestingTerms) private vestingTerms;

    modifier onlyWallet() {
        require(msg.sender == wallet, "Only wallet is allowed to proceed");
        _;
    }

    /// @param _token Address of ERC20 token associated with this vesting contract
    /// @param _wallet Address of account that starts and stops vesting for different parties
    constructor(IERC20 _token, address _wallet) {
        token = _token;
        wallet = _wallet;
    }

    function getVestingTerms(address receiver) external view override returns (VestingTerms memory) {
        return vestingTerms[receiver];
    }

    function startVesting(address receiver, VestingTerms calldata terms) public override onlyWallet {
        require(receiver != address(0), "Receiver cannot be 0.");
        require(terms.amount > 0, "Amount must be > 0.");
        require(terms.startTime != 0, "Start time must be set.");
        require(terms.period > 0, "Period must be set.");
        require(terms.claimed == 0, "Can not start vesting with already claimed tokens.");
        assert(isScheduleValid(terms));
        require(!isScheduleValid(vestingTerms[receiver]), "Vesting already started for account.");

        vestingTerms[receiver] = terms;
        token.transferFrom(wallet, address(this), terms.amount);

        emit VestingAdded(receiver, terms);
    }

    function startVestingBatch(address[] calldata receivers, VestingTerms[] calldata terms)
        external
        override
        onlyWallet
    {
        require(receivers.length > 0, "Zero receivers.");
        require(receivers.length == terms.length, "Terms and receivers mush have same length.");

        for (uint256 i = 0; i < receivers.length; i++) {
            startVesting(receivers[i], terms[i]);
        }
    }

    function claim() external override {
        claim(type(uint256).max);
    }

    function claim(uint256 value) public override {
        require(value > 0, "Claiming 0 tokens.");
        VestingTerms memory terms = vestingTerms[msg.sender];
        require(isScheduleValid(terms), "No vesting data for sender.");

        uint256 claimableTokens = _claimable(terms);
        if (value == type(uint256).max) {
            value = claimableTokens;
        } else {
            require(value <= claimableTokens, "Claiming amount exceeds allowed tokens.");
        }

        vestingTerms[msg.sender].claimed += value;
        token.transfer(msg.sender, value);

        emit VestingClaimed(msg.sender, value);
    }

    function transferVesting(address receiver) external override {
        require(receiver != address(0), "Receiver cannot be 0.");
        require(!isScheduleValid(vestingTerms[receiver]), "Vesting already started for receiver.");
        vestingTerms[receiver] = vestingTerms[msg.sender];
        delete vestingTerms[msg.sender];

        emit VestingTransferred(msg.sender, receiver);
    }

    function stopVesting(address receiver) external override onlyWallet {
        require(receiver != address(0), "Receiver cannot be 0.");

        VestingTerms memory terms = vestingTerms[receiver];
        require(isScheduleValid(terms), "No vesting data for receiver.");
        delete vestingTerms[receiver];

        // transfer tokens that are not claimed yet
        if (terms.amount > terms.claimed) {
            token.transfer(wallet, terms.amount - terms.claimed);
        }

        emit VestingRemoved(receiver);
    }

    function claimable(address receiver) external view override returns (uint256) {
        return _claimable(vestingTerms[receiver]);
    }

    function _claimable(VestingTerms memory terms) private view returns (uint256 claimableTokens) {
        if (terms.startTime < block.timestamp) {
            uint256 maxTokens = (block.timestamp >= terms.startTime + terms.period)
                ? (terms.amount)
                : (terms.amount * (block.timestamp - terms.startTime)) / terms.period;

            if (terms.claimed < maxTokens) {
                claimableTokens = maxTokens - terms.claimed;
            }
        }
    }

    function isScheduleValid(VestingTerms memory terms) private pure returns (bool) {
        return terms.startTime != 0;
    }
}