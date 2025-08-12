// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRebaseToken
 * @author Alexander Scherbatyuk
 * @notice This is the interface for the RebaseToken contract.
 */
interface IRebaseToken {
    function mint(address _to, uint256 _amount, uint256 _interestRate) external;
    function burn(address _from, uint256 _amount) external;
    function balanceOf(address _user) external view returns (uint256);
    function getUserInterestRate(address _user) external view returns (uint256);
    function getInterestRate() external view returns (uint256);
    function grantMintAndBurnRole(address _to) external;
}
