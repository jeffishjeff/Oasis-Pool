# Oasis-Pool

A shared, pre-funded liquidity environment for testing Uniswap v4 hooks in live markets.

### Problem

Hook builders face a catch-22: Testing solely on testnets misses real-world variables like gas costs, MEV, and user behaviors. Furthermore, it is not able to validate yield or other expectations. Yet testing in live markets requires bootstrapping real liquidity and flow. As a result, many promising hook projects stall between prototype and production.

### Solution

The Oasis Pool is a public-good Uniswap v4 environment seeded with stable assets and powered by a special Host Hook, which can host Guest Hooks one at a time and forwards the expected callbacks, enabling developers to validate behavior under real swap and gas conditions without bootstrapping liquidity or risking user experience. This PoC prioritizes single-guest and stable pairs only for safety and simplicity, with planned upgrades for multi-guests, volatile pairs, and additional features after validation.

### How It Works

- Oasis PoolKey = {USDC, USDT, 0x800000, 1, HostHook}
- IHostHook is IHooks
  - attach(): validate Guest Hook address then register it
  - detach(): remove registered Guest Hook
- HostHook is IHostHook
  - address(this) & Hooks.ALL_HOOK_MASK == Hooks.ALL_HOOK_MASK
  - before/after(): forward to Guest Hook if it is expected, default value for lpFeeOverride is 0x400000

### Benefits to the Ecosystem

Provide a low-risk path from prototype to production
Enables live testing without bootstrapping TVL
Surfaces gas, MEV, and revert issues early
Establishes a public-good infrastructure for v4 innovation
