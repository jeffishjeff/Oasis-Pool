// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";
import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap-v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap-v4-core/libraries/LPFeeLibrary.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap-v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap-v4-core/types/BeforeSwapDelta.sol";
import {PoolId} from "@uniswap-v4-core/types/PoolId.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IHostHook} from "./interfaces/IHostHook.sol";

/// @notice HostHook contract that forwards hook calls to the attached GuestHook
contract HostHook is IHostHook, Ownable2Step {
    using Hooks for IHooks;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    IPoolManager public immutable poolManager;
    mapping(PoolId => IHooks) public guestHookOf;

    modifier onlyPoolManager() {
        _onlyPoolManager();
        _;
    }

    function _onlyPoolManager() internal view {
        require(msg.sender == address(poolManager), NotPoolManager());
    }

    constructor(IPoolManager _poolManager) Ownable(msg.sender) {
        // ensures that the HostHook has all the hook permissions
        require(uint160(address(this)) & Hooks.ALL_HOOK_MASK == Hooks.ALL_HOOK_MASK, InvalidHostHookAddress());

        poolManager = _poolManager;
    }

    // ***************************
    // *** IHostHook Functions ***
    // ***************************

    /// @inheritdoc IHostHook
    function attach(PoolKey memory poolKey, IHooks guestHook) external onlyOwner {
        PoolId poolId = poolKey.toId();
        // only one guest hook can be attached to a pool at a time
        require(address(guestHookOf[poolId]) == address(0), PoolOccupied());
        // check the validity of guest hook address, for a dynamic fee pool
        require(guestHook.isValidHookAddress(poolKey.fee), InvalidGuestHookAddress());

        guestHookOf[poolId] = guestHook;

        emit Attachment(poolId, guestHook);
    }

    /// @inheritdoc IHostHook
    function detach(PoolKey memory poolKey) external onlyOwner {
        PoolId poolId = poolKey.toId();

        delete guestHookOf[poolId];
        // reset the LP fee that might have been set by guest hook
        poolManager.updateDynamicLPFee(poolKey, 0);

        emit Detachment(poolId);
    }

    /// @inheritdoc IHostHook
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external {
        require(msg.sender == address(guestHookOf[key.toId()]), NotGuestHook());

        poolManager.updateDynamicLPFee(key, newDynamicLPFee);
    }

    // ***************************
    // **** IHooks Functions *****
    // ***************************

    /// @inheritdoc IHooks
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        external
        onlyPoolManager
        returns (bytes4)
    {
        // pool must support dynamic fee, if guest hook expects fixed fee, call updateDynamicLPFee() in afterInitialize()
        require(key.fee == LPFeeLibrary.DYNAMIC_FEE_FLAG, InvalidPoolKey());
        IHooks guestHook = guestHookOf[key.toId()];

        return guestHook.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG)
            ? guestHook.beforeInitialize(sender, key, sqrtPriceX96)
            : this.beforeInitialize.selector;
    }

    /// @inheritdoc IHooks
    function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        external
        onlyPoolManager
        returns (bytes4)
    {
        IHooks guestHook = guestHookOf[key.toId()];

        return guestHook.hasPermission(Hooks.AFTER_INITIALIZE_FLAG)
            ? guestHook.afterInitialize(sender, key, sqrtPriceX96, tick)
            : this.afterInitialize.selector;
    }

    /// @inheritdoc IHooks
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        IHooks guestHook = guestHookOf[key.toId()];

        return guestHook.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG)
            ? guestHook.beforeAddLiquidity(sender, key, params, hookData)
            : this.beforeAddLiquidity.selector;
    }

    /// @inheritdoc IHooks
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        IHooks guestHook = guestHookOf[key.toId()];

        if (guestHook.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG)) {
            (bytes4 selector, BalanceDelta hookDelta) =
                guestHook.afterAddLiquidity(sender, key, params, delta, feesAccrued, hookData);

            // if guest hook took currency, the original caller must have explicitly allowed it by signaling via hookData
            require(
                (hookDelta.amount0() <= 0 && hookDelta.amount1() <= 0)
                    || (hookData.length >= 32
                        && abi.decode(hookData[hookData.length - 32:], (uint160))
                            == Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG),
                InvalidHookDelta()
            );

            return (selector, hookDelta);
        }

        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @inheritdoc IHooks
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        IHooks guestHook = guestHookOf[key.toId()];

        return guestHook.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG)
            ? guestHook.beforeRemoveLiquidity(sender, key, params, hookData)
            : this.beforeRemoveLiquidity.selector;
    }

    /// @inheritdoc IHooks
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        IHooks guestHook = guestHookOf[key.toId()];

        if (guestHook.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)) {
            (bytes4 selector, BalanceDelta hookDelta) =
                guestHook.afterRemoveLiquidity(sender, key, params, delta, feesAccrued, hookData);

            // if guest hook took currency, the original caller must have explicitly allowed it by signaling via hookData
            require(
                (hookDelta.amount0() <= 0 && hookDelta.amount1() <= 0)
                    || (hookData.length >= 32
                        && abi.decode(hookData[hookData.length - 32:], (uint160))
                            == Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG),
                InvalidHookDelta()
            );

            return (selector, hookDelta);
        }

        return (this.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @inheritdoc IHooks
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        IHooks guestHook = guestHookOf[key.toId()];

        if (guestHook.hasPermission(Hooks.BEFORE_SWAP_FLAG)) {
            try guestHook.beforeSwap(sender, key, params, hookData) returns (
                bytes4 selector, BeforeSwapDelta hookDelta, uint24 lpFeeOverride
            ) {
                // if guest hook took currency, the original caller must have explicitly allowed it by signaling via hookData
                require(
                    (hookDelta.getSpecifiedDelta() <= 0 && hookDelta.getUnspecifiedDelta() <= 0)
                        || (hookData.length >= 32
                            && abi.decode(hookData[hookData.length - 32:], (uint160))
                                == (Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG)),
                    InvalidHookDelta()
                );

                return (selector, hookDelta, lpFeeOverride);
            } catch {}
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @inheritdoc IHooks
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, int128) {
        IHooks guestHook = guestHookOf[key.toId()];

        if (guestHook.hasPermission(Hooks.AFTER_SWAP_FLAG)) {
            try guestHook.afterSwap(sender, key, params, delta, hookData) returns (bytes4 selector, int128 hookDelta) {
                // if guest hook took currency, the original caller must have explicitly allowed it by signaling via hookData
                require(
                    (hookDelta <= 0)
                        || (hookData.length >= 32
                            && abi.decode(hookData[hookData.length - 32:], (uint160))
                                == (Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG)),
                    InvalidHookDelta()
                );

                return (selector, hookDelta);
            } catch {}
        }

        return (this.afterSwap.selector, 0);
    }

    /// @inheritdoc IHooks
    function beforeDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        IHooks guestHook = guestHookOf[key.toId()];

        return guestHook.hasPermission(Hooks.BEFORE_DONATE_FLAG)
            ? guestHook.beforeDonate(sender, key, amount0, amount1, hookData)
            : this.beforeDonate.selector;
    }

    /// @inheritdoc IHooks
    function afterDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        IHooks guestHook = guestHookOf[key.toId()];

        return guestHook.hasPermission(Hooks.AFTER_DONATE_FLAG)
            ? guestHook.afterDonate(sender, key, amount0, amount1, hookData)
            : this.afterDonate.selector;
    }
}
