// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap-v4-core/types/PoolId.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";

/// @notice Interface for the HostHook contract
interface IHostHook is IHooks {
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
