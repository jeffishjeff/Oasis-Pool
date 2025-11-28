// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";
import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap-v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap-v4-core/libraries/LPFeeLibrary.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "@uniswap-v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap-v4-core/types/BeforeSwapDelta.sol";
import {PoolId} from "@uniswap-v4-core/types/PoolId.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IHostHook} from "./interfaces/IHostHook.sol";

/// @notice HostHook contract that forwards hook calls to the attached GuestHook
contract HostHook is IHostHook, Ownable2Step {
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;

    IPoolManager public immutable poolManager;
    mapping(PoolId => IHooks) public guestHookOf;

    modifier onlyPoolManager() {
        _onlyPoolManager();
        _;
    }

    function _onlyPoolManager() internal view {
        require(msg.sender == address(poolManager), NotPoolManager());
    }

    constructor(IPoolManager _poolManager, address owner) Ownable(owner) {
        // ensures that the HostHook has all the hook permissions
        require(uint160(address(this)) & Hooks.ALL_HOOK_MASK == Hooks.ALL_HOOK_MASK, InvalidHostHookAddress());

        poolManager = _poolManager;
    }

    // ***************************
    // *** IHostHook Functions ***
    // ***************************

    /// @inheritdoc IHostHook
    function attach(PoolKey memory poolKey, IHooks guestHook, uint24 fee) external onlyOwner {
        PoolId poolId = poolKey.toId();
        // only one guest hook can be attached to a pool at a time
        require(address(guestHookOf[poolId]) == address(0), PoolOccupied());
        // check the validity of guest hook address (poolKey.fee should be dynamic)
        require(guestHook.isValidHookAddress(poolKey.fee), InvalidGuestHookAddress());

        // set the guest hook (and initial / fixed LP fee)
        guestHookOf[poolId] = guestHook;
        if (!fee.isDynamicFee()) poolManager.updateDynamicLPFee(poolKey, fee);

        emit Attachment(poolId, guestHook);
    }

    /// @inheritdoc IHostHook
    function detach(PoolKey memory poolKey) external onlyOwner {
        PoolId poolId = poolKey.toId();
        IHooks guestHook = guestHookOf[poolId];

        // clear the guest hook and LP fee
        delete guestHookOf[poolId];
        poolManager.updateDynamicLPFee(poolKey, 0);

        emit Detachment(poolId, guestHook);
    }

    /// @inheritdoc IHostHook
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external {
        require(msg.sender == address(guestHookOf[key.toId()]), NotGuestHook());

        // update the dynamic LP fee in the pool manager
        poolManager.updateDynamicLPFee(key, newDynamicLPFee);
    }

    // ************************
    // *** IHooks Functions ***
    // ************************

    /// @inheritdoc IHooks
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        external
        onlyPoolManager
        returns (bytes4)
    {
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

            int128 delta0 = hookDelta.amount0();
            int128 delta1 = hookDelta.amount1();
            bool permitPositiveDelta = _permitPositiveDelta(hookData, Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG);

            // if guest hook took currency, make sure it is explicited permitted by the original sender or zero it out
            if (delta0 > 0 && !permitPositiveDelta) delta0 = 0;
            if (delta1 > 0 && !permitPositiveDelta) delta1 = 0;

            hookDelta = toBalanceDelta(delta0, delta1);

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

            int128 delta0 = hookDelta.amount0();
            int128 delta1 = hookDelta.amount1();
            bool permitPositiveDelta = _permitPositiveDelta(hookData, Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG);

            // if guest hook took currency, make sure it is explicited permitted by the original sender or zero it out
            if (delta0 > 0 && !permitPositiveDelta) delta0 = 0;
            if (delta1 > 0 && !permitPositiveDelta) delta1 = 0;

            hookDelta = toBalanceDelta(delta0, delta1);

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
                // no guard against guest hook taking currency, as Tycho only supports composable hooks (i.e. does not use hookData)
                // instead rely on solver having simulated the swap and understood the implications
                /*
                int128 specifiedDelta = hookDelta.getSpecifiedDelta();
                int128 unspecifiedDelta = hookDelta.getUnspecifiedDelta();
                bool permitPositiveDelta = _permitPositiveDelta(hookData, Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);

                // if guest hook took currency, make sure it is explicited permitted by the original sender or zero it out
                if (specifiedDelta > 0 && !permitPositiveDelta) specifiedDelta = 0;
                if (unspecifiedDelta > 0 && !permitPositiveDelta) unspecifiedDelta = 0;

                hookDelta = toBeforeSwapDelta(specifiedDelta, unspecifiedDelta);
                */

                return (selector, hookDelta, lpFeeOverride);
            } catch Panic(uint256 code) {
                emit RevertPanic(guestHook, code);
            } catch Error(string memory reason) {
                emit RevertString(guestHook, reason);
            } catch (bytes memory data) {
                if (data.length < 4) {
                    emit RevertEmpty(guestHook);
                } else {
                    bytes4 selector;
                    assembly { selector := mload(add(data, 32)) }

                    emit RevertCustom(guestHook, selector, data);
                }
            }
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
                // no guard against guest hook taking currency, as Tycho only supports composable hooks (i.e. does not use hookData)
                // instead rely on solver having simulated the swap and understood the implications
                /*
                if (hookDelta > 0 && !_permitPositiveDelta(hookData, Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG)) {
                    hookDelta = 0;
                }
                */

                return (selector, hookDelta);
            } catch Panic(uint256 code) {
                emit RevertPanic(guestHook, code);
            } catch Error(string memory reason) {
                emit RevertString(guestHook, reason);
            } catch (bytes memory data) {
                if (data.length < 4) {
                    emit RevertEmpty(guestHook);
                } else {
                    bytes4 selector;
                    assembly { selector := mload(add(data, 32)) }

                    emit RevertCustom(guestHook, selector, data);
                }
            }
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

    // ************************
    // *** Helper Functions ***
    // ************************

    function _permitPositiveDelta(bytes calldata hookData, uint160 permission) internal pure returns (bool) {
        // original caller must have explicitly allowed it by signaling via an extra word in the hookData
        // doesn't need to be IHooks, just casting to use hasPermission() for convenience
        // generally it's easiest to just append the guest hook address itself
        return hookData.length >= 32 && abi.decode(hookData[hookData.length - 32:], (IHooks)).hasPermission(permission);
    }
}
