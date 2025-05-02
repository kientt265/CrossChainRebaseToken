// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Rebase Token
 * @author [Your Name/Organization]
 * @notice Implements a cross-chain ERC20 token where balances increase automatically over time.
 * @dev This contract uses a rebasing mechanism based on a per-second interest rate.
 * The global interest rate can only increase or stay the same. Each user gets assigned
 * the prevailing global interest rate upon their first interaction involving balance updates.
 * Balances are calculated dynamically in the `balanceOf` function.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {

    error RebaseToken__InterestRateCanOnlyIncrease(uint256 s_interestRate,uint256 _newInterestRate);

    event  InterestRateSet(uint256 _newInterestRate);
    // Represents 1 with 18 decimal places for fixed-point math
    uint256 private constant PRECISION_FACTOR = 1e18;

    // Global interest rate per second (scaled by PRECISION_FACTOR)
    // Example: 5e10 represents 0.00000005 or 0.000005% per second
    uint256 private s_interestRate = 5e10;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    /**
     * @notice Initializes the Rebase Token with a name and symbol.
     */
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    // Maps users to their specific interest rate (set at interaction time)
    mapping(address => uint256) private s_userInterestRate;

    // Maps users to the block timestamp of their last balance update/interest accrual
    mapping(address => uint256) private s_userLastUpdatedAtTimestamp;

    // Constructor, Events, Errors, and Functions will follow...

    /**
     * @notice Sets the global interest rate for the token contract.
     * @dev Reverts if the proposed rate is lower than the current rate.
     * Emits an {InterestRateSet} event on success.
     * @param _newInterestRate The desired new global interest rate per second (scaled by PRECISION_FACTOR).
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner{
        // Ensure the interest rate never decreases
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyIncrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

        /**
     * @notice Calculates the interest multiplier for a user since their last update.
     * @dev The multiplier represents (1 + (user_rate * time_elapsed)).
     * The result is scaled by PRECISION_FACTOR.
     * @param _user The address of the user.
     * @return linearInterest The calculated interest multiplier (scaled).
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) {
        uint256 lastUpdateTimestamp = s_userLastUpdatedAtTimestamp[_user];
        // If never updated, assume current time to avoid huge elapsed time
        if (lastUpdateTimestamp == 0) {
            // Or alternatively, could set it during mint/transfer in initial setup
            lastUpdateTimestamp = block.timestamp;
        }

        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;

        // Calculate interest part: user_rate * time_elapsed (already scaled by 1e18 * seconds)
        uint256 interestPart = s_userInterestRate[_user] * timeElapsed;

        // Calculate multiplier: 1 + interest part
        // PRECISION_FACTOR represents 1 (scaled)
        linearInterest = PRECISION_FACTOR + interestPart;
        // Example: If rate is 10% per second (scaled) and 2 seconds pass:
        // interestPart = (0.1 * 1e18) * 2 = 0.2 * 1e18
        // linearInterest = 1e18 + 0.2 * 1e18 = 1.2 * 1e18 (representing a 1.2x multiplier)
    }

    /**
     * @notice Gets the dynamic balance of an account, including accrued interest.
     * @dev Overrides the standard ERC20 balanceOf function.
     * Calculates balance as: Principal * (1 + (User Rate * Time Elapsed)).
     * Uses fixed-point math.
     * @param _user The address to query the balance for.
     * @return The calculated total balance (principal + accrued interest).
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // Get the stored principal balance (this is what _mint/_burn directly affects)
        // super.balanceOf() calls the original ERC20 implementation.
        uint256 principalBalance = super.balanceOf(_user);

        // If principal is zero, calculated balance is also zero
        if (principalBalance == 0) {
            return 0;
        }

        // Get the interest multiplier (scaled by 1e18)
        uint256 interestMultiplier = _calculateUserAccumulatedInterestSinceLastUpdate(_user);

        // Calculate final balance: (Principal * Multiplier) / PrecisionFactor
        // Principal is already scaled (implicitly by 1e18 as it's an ERC20 balance)
        // Multiplier is scaled by 1e18
        // Result of multiplication is scaled by 1e36
        // Divide by PRECISION_FACTOR (1e18) to get the final balance scaled by 1e18
        return (principalBalance * interestMultiplier) / PRECISION_FACTOR;
    }

    /**
     * @notice Calculates accrued interest, mints it, and updates the user's last timestamp.
     * @dev This should be called *before* operations that rely on an up-to-date principal balance
     * or that modify the principal (e.g., mint, transfer, burn).
     * @param _user The address for which to accrue interest.
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 principalBalance = super.balanceOf(_user);

        // Avoid calculations if principal is zero
        if (principalBalance == 0) {
            // Still update timestamp if they have a rate assigned, might receive tokens later
            if(s_userInterestRate[_user] > 0) {
                 s_userLastUpdatedAtTimestamp[_user] = block.timestamp;
            }
            return;
        }

        uint256 totalBalanceWithInterest = balanceOf(_user); // Use our overridden balanceOf

        // Interest to mint is the difference between the calculated total and the stored principal
        uint256 interestToMint = totalBalanceWithInterest - principalBalance;

        // Mint the accrued interest amount if there is any
        if (interestToMint > 0) {
            // _mint is the internal function from the parent ERC20 contract
            _mint(_user, interestToMint);
        }

        // Crucially, update the timestamp AFTER calculating and minting interest
        s_userLastUpdatedAtTimestamp[_user] = block.timestamp;
    }

      /**
     * @notice Mints new principal tokens to a user's account.
     * @dev Accrues existing interest first, then sets the user's interest rate
     * to the current global rate, and finally mints the new principal amount.
     * @param _to The recipient address.
     * @param _amount The amount of principal tokens to mint.
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE){
        // 1. Calculate and mint any pending interest for the recipient FIRST
        _mintAccruedInterest(_to);

        // 2. Set (or update) the user's personal interest rate to the current global rate
        s_userInterestRate[_to] = s_interestRate;
        // Note: Timestamp is updated inside _mintAccruedInterest

        // 3. Mint the requested principal amount using the inherited internal function
        _mint(_to, _amount); // This updates the value returned by super.balanceOf()
    }

        /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from The user to burn the tokens from
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE){ // Note: Access control should be added
        // Check if user wants to burn entire balance
        if (_amount == type(uint256).max) {
            // Update amount to current full balance including interest
            _amount = balanceOf(_from);
        }

        // Update balance with accrued interest first
        _mintAccruedInterest(_from);
        // Burn the specified (potentially updated) amount
        _burn(_from, _amount);
    }

    /**
     * @notice Gets the specific interest rate assigned to a user.
     * @param _user The address of the user.
     * @return The user's assigned interest rate per second (scaled).
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }


    function getInterestRate() external view returns(uint256) {
        return s_interestRate;
    }
    function transfer(address _recipient, uint256 _amount) public override returns(bool){
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if(_amount == type(uint256).max){
            _amount = balanceOf(msg.sender);
        }
        if(balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns(bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if(_amount == type(uint256).max){
            _amount = balanceOf(_sender);
        }
        if(balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    function grantMintAndBurnRole(address _account) external onlyOwner {
    _grantRole(MINT_AND_BURN_ROLE, _account);
    // Optionally emit an event
    // emit RoleGranted(MINT_AND_BURN_ROLE, _account, msg.sender);
}
} // End of RebaseToken contract
