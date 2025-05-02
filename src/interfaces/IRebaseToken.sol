// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRebaseToken Interface
 * @notice Defines the functions the Vault contract needs to call on the RebaseToken contract.
 */
interface IRebaseToken {
    /**
     * @notice Mints new tokens to a specified address.
     * @param _to The address to receive the minted tokens.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external;

    /**
     * @notice Burns tokens from a specified address.
     * @param _from The address whose tokens will be burned.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external;

    function getUserInterestRate(address _user) external view returns (uint256);

    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external;
}