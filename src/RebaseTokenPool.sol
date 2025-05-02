// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
// import {IPoolV1} from "@ccip/contracts/src/v0.8/ccip/interfaces/IPoolV1.sol"; // Explicit import for clarity
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol"; // Use version compatible with CCIP contracts
import "./interfaces/IRebaseToken.sol";
// Assume an interface for your custom Rebasing Token exists
// interface IRebaseToken is IERC20 {
//     function burn(address _from, uint256 _amount) external;
//     function mint(address _to, uint256 _amount, uint256 _interestRate) external;
//     function getUserInterestRate(address _account) external view returns (uint256);
// }

abstract contract RebaseTokenPool is TokenPool {
    // Constructor and functions follow
    constructor(IERC20 _token, address[] memory _allowlist, address _rnmProxy, address _router) TokenPool(_token, _allowlist, _rnmProxy, _router) {

    }

    function lockOrBurn(
    Pool.LockOrBurnInV1 calldata lockOrBurnIn
  ) external override  returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut) {
     _validateLockOrBurn(lockOrBurnIn);

        // 2. Decode the original sender's address
        // The original sender initiated the transfer on the source chain.
        address originalSender = lockOrBurnIn.originalSender;

        // 3. Get the user's current interest rate from the Rebasing Token contract
        // We need to cast the stored IERC20 token address (i_token) to our custom interface
        // Requires intermediate cast to address
        IRebaseToken rebaseToken = IRebaseToken(address(i_token));
        uint256 userInterestRate = rebaseToken.getUserInterestRate(originalSender);

        // 4. Burn the specified amount of tokens FROM THE POOL'S BALANCE
        // IMPORTANT: CCIP transfers tokens *to* the pool *before* calling lockOrBurn.
        // The pool must burn tokens it now holds.
        rebaseToken.burn(address(this), lockOrBurnIn.amount);

        // 5. Prepare the output data for CCIP
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            // Get the address of the corresponding token contract on the destination chain
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            // ABI encode the user's interest rate to send it cross-chain
            destPoolData: abi.encode(userInterestRate)
        });

  }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
       // Ensure only the CCIP Router can call this
        returns (Pool.ReleaseOrMintOutV1 memory) // Return type specification
    {
        // 1. Perform essential security checks from the base contract
        _validateReleaseOrMint(releaseOrMintIn);

        // 2. Decode the user's interest rate from the incoming poolData
        // This data was encoded in `destPoolData` by the source chain's `lockOrBurn` function.
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        // 3. Mint tokens to the final receiver using the custom mint function
        // Cast the token address to our custom interface to call the specific mint function.
        IRebaseToken rebaseToken = IRebaseToken(address(i_token));
        rebaseToken.mint(
            releaseOrMintIn.receiver,     // The final recipient address
            releaseOrMintIn.amount,       // The amount transferred
            userInterestRate              // The interest rate from the source chain
        );

        // 4. Return the amount that was successfully minted
        // In this simple case, it's the same as the input amount.
        return Pool.ReleaseOrMintOutV1({
            destinationAmount: releaseOrMintIn.amount
        });
    }
}