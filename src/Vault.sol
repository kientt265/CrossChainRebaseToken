// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import  "./interfaces/IRebaseToken.sol";
// Forward declaration for the interface we will create


contract Vault {

    // Event emitted when a user deposits ETH
    event Deposit(address indexed user, uint256 amount);
    // Event emitted when a user redeems tokens for ETH
    event Redeem(address indexed user, uint256 amount);

    // Custom error for failed ETH transfer during redemption
    error Vault_RedeemFailed();

    // State variable to store the RebaseToken contract address
    IRebaseToken private immutable i_rebaseToken;

    // Constructor to set the immutable token address
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }



      // Public getter for the RebaseToken address
    /**
     * @notice Returns the address of the RebaseToken contract this vault interacts with.
     * @return address The address of the RebaseToken contract.
     */
    function getRebaseTokenAddress() external view returns (address) {
        // Cast the interface type back to address for the return value
        return address(i_rebaseToken);
    }

    /**
     * @notice Allows users to deposit ETH and receive an equivalent amount of RebaseTokens.
     * @dev Mints tokens based on msg.value sent with the transaction.
     */
    function deposit() external payable {
        // msg.value is the amount of ETH sent with the call
        uint256 amountToMint = msg.value;

        // Ensure some ETH was actually sent
        if (amountToMint == 0) {
            revert("Deposit amount must be greater than zero"); // Or use a custom error
        }

        // Call the mint function on the RebaseToken contract
        // msg.sender is the address that called this deposit function
        i_rebaseToken.mint(msg.sender, amountToMint);

        // Emit an event to log the deposit
        emit Deposit(msg.sender, amountToMint);
    }

      /**
     * @notice Allows users to burn their RebaseTokens and receive the equivalent amount of ETH.
     * @param _amount The amount of RebaseTokens to burn and redeem for ETH.
     */
    function redeem(uint256 _amount) external {
        // Ensure the user is redeeming a non-zero amount
        if (_amount == 0) {
            revert("Redeem amount must be greater than zero"); // Or use a custom error
        }

        // --- Checks-Effects-Interactions Pattern ---

        // Effect: Burn the user's tokens first.
        // This modifies the state *before* the external call.
        i_rebaseToken.burn(msg.sender, _amount);

        // Interaction: Send ETH back to the user.
        // Using low-level .call for ETH transfer is recommended practice.
        (bool success, ) = payable(msg.sender).call{value: _amount}("");

        // Check: Verify the external call (ETH transfer) succeeded.
        if (!success) {
            revert Vault_RedeemFailed();
        }

        // Emit an event to log the redemption
        emit Redeem(msg.sender, _amount);
    }

        /**
     * @notice Allows the contract to receive plain ETH transfers (e.g., for rewards).
     */
    receive() external payable {
        // This function can optionally emit an event or perform other logic,
        // but here it simply accepts the ETH, increasing the contract's balance.
    }
}