// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap-v4-core/types/PoolId.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";

/// @notice Interface for the HostHook contract
interface IHostHook is IHooks {
    /// @notice Thrown when the host hook address is invalid
    error InvalidHostHookAddress();
    /// @notice Thrown when the guest hook address is invalid
    error InvalidGuestHookAddress();
    /// @notice Thrown when the pool key is invalid
    error InvalidPoolKey();
    /// @notice Thrown when the hook delta returned by guest hook is invalid
    error InvalidHookDelta();
    /// @notice Thrown when trying to attach a guest hook to an occupied pool
    error PoolOccupied();
    /// @notice Thrown when message sender is not the guest hook of the pool
    error NotGuestHook();
    /// @notice Thrown when message sender is not the pool manager
    error NotPoolManager();

    /// @notice Emitted when a guest hook call reverts with an empty reason
    /// @param guestHook The guest hook that reverted
    event RevertEmpty(IHooks guestHook);
    /// @notice Emitted when a guest hook call reverts with a panic code
    /// @param guestHook The guest hook that reverted
    /// @param code The panic code
    event RevertPanic(IHooks guestHook, uint256 code);
    /// @notice Emitted when a guest hook call reverts with a string reason
    /// @param guestHook The guest hook that reverted
    /// @param reason The revert reason
    event RevertString(IHooks guestHook, string reason);
    /// @notice Emitted when a guest hook call reverts with a custom error
    /// @param guestHook The guest hook that reverted
    /// @param selector The selector of the custom error
    /// @param data The data of the custom error
    event RevertCustom(IHooks guestHook, bytes4 selector, bytes data);

    /// @notice Emitted when a guest hook is attached to a pool
    /// @param poolId The pool identifier
    /// @param guestHook The guest hook that is attached
    event Attachment(PoolId indexed poolId, IHooks indexed guestHook);

    /// @notice Emitted when the guest hook is detached from a pool
    /// @param poolId The pool identifier
    event Detachment(PoolId indexed poolId);

    /// @notice Attaches a guest hook to a pool
    /// @param poolKey The key of the pool to attach to
    /// @param guestHook The guest hook to attach
    function attach(PoolKey memory poolKey, IHooks guestHook) external;

    /// @notice Detaches the guest hook from a pool
    /// @param poolKey The key of the pool to detach from
    function detach(PoolKey memory poolKey) external;

    /// @notice Updates the dynamic LP fee for a pool
    /// @dev only callable by the current guest hook of the pool
    /// @param key The key of the pool to update
    /// @param newDynamicLPFee The new dynamic LP fee to set
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external;

    /// @notice Gets the pool manager of this host hook
    /// @return The pool manager
    function poolManager() external view returns (IPoolManager);

    /// @notice Gets the guest hook attached to a pool
    /// @param poolId The pool identifier
    /// @return The guest hook attached to the pool
    function guestHookOf(PoolId poolId) external view returns (IHooks);
}
