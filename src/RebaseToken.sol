// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin-contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Alexander Scherbatyuk
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is global interest rate at the time of depositing.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; // 10^(-8) == 1 / 10^8
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate in the contract.
     * @param _newInterestRate The new interest rate to set.
     * @dev The interest rate can only decrease.
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Set the new interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(s_interestRate);
    }

    /**
     * @notice Get the principal balance of a user. This is the number of tokens that have currently been minted to the user,
     * not including any interest that has been accrued since the last time user interacted with the protocol.
     * @param _user The address of the user to get the principal balance for.
     * @return The principal balance of the user.
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault.
     * @param _to The address of the user to calculate the interest for.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        // check
        // need to add checks!!!

        // effect
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);

        // interaction
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault.
     * @param _from The address of the user to burn the tokens from.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // mitigation against any dust tokens that are left over
        // aavee v3 approach, also included to aave A token
        // if (_amount == type(uint256).max) {
        //     _amount = balanceOf(_from);
        // }
        // effect
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Calculate the interest that has been accrued since the last update for a user.
     * @notice (principle balance) + same interest that has accured
     * @param _user The user to calculate the balance for.
     * @return The balance of the user including the interest that has been accrued since the last update.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principal balacne of the user (the number of tokens that have actually been minted to the user)
        // multiply the principal balance by the interest that has been accrued accumulated in the time since the last update
        uint256 currentPrincipalBalance = super.balanceOf(_user);
        if (currentPrincipalBalance == 0) {
            return 0;
        }
        //
        return currentPrincipalBalance * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer the user tokens to another user.
     * @param _recipient The address of the user to transfer the tokens to.
     * @param _amount The amount of tokens to transfer.
     * @return bool True if the transfer is successful, false otherwise.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        // known feature that goes against the protocol principles is that users can use a deposit at higher interest earlier
        // than transfer some tokens to another wallet with higher deposit and get higher interest rate for later deposit
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer the user tokens from one user to another.
     * @param _sender The address of the user to transfer the tokens from.
     * @param _recipient The address of the user to transfer the tokens to.
     * @param _amount The amount of tokens to transfer.
     * @return bool True if the transfer is successful, false otherwise.
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        // known feature that goes against the protocol principles is that users can use a deposit at higher interest earlier
        // than transfer some tokens to another wallet with higher deposit and get higher interest rate for later deposit
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculate the interest that has been accrued since the last update for a user.
     * @param _user The user to calculate the interest accumulated for.
     * @return linearInterest The interest that has been accumulated since the last update.
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) {
        // we need to calculate the interest that has been accumulated since the last update
        // this is going to be linear growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of linear growth
        // principal amount (1 + user interest rate * time elapsed)
        // deposit: 10 tokens
        // interest rate: 0.5 tokens per second
        // time elapsed: 2 seconds
        // interest accumulated: 10 * (10 * 0.5 * 2)
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (e.g. burn, mint, transfer).
     * @param _user The user to mint the accrued interest to.
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens  that have been minted to the user - principle balance.
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // (3) calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // (4) set the users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // (5) call _mint to mint tokens to the user
        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Get the interest rate for a user.
     * @param _user The address of the user to get the interest rate for.
     * @return The interest rate for the user.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Get the global interest rate that is set in the contract.
     * @notice Any future depositors will receive this interest rate.
     * @return The global interest rate for the protocol.
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// CEI:
// Check
// Effect
// Interaction
