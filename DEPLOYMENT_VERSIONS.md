# Deployed implementation versions

This document summarizes what each upgradeable **implementation** adds relative to the previous line, and records **which proxies / beacons the repo’s scripts target** for production vs pre-production on Base (chain id 8453).

**Important:** On-chain truth is the implementation address behind each proxy (EIP-1967 slot) or the implementation pointed to by each `UpgradeableBeacon`. Treat the tables below as “configured in this repo’s scripts / intended rollout.” Before auditing or announcing live versions, confirm with a block explorer or `cast`/RPC read.

## What each version changes

### FriendKey

| Line | Contract | Changes (high level) |
|------|----------|----------------------|
| V1 | `FriendKey.sol` | Original ERC-1155 bonding curve, fees via `FriendRoomManager`, staking via beacon proxies. |
| V2 | `FriendKeyV2.sol` | `@custom:oz-upgrades-from FriendKey`. Integrates dispatch fee reads from `FriendPool`, `canRegisterRoom` visibility for room limits, and related registration / `_update` behavior aligned with room manager and pool. Deployed as a **UUPS** upgrade of the same proxy as V1. |

### FriendPool

| Line | Contract | Changes (high level) |
|------|----------|----------------------|
| V1 | `FriendPool.sol` | Reserves per token, `pull` from `FriendKey`, DLN dispatch, flat `dispatchFee`. |
| V2 | `FriendPoolV2.sol` | `@custom:oz-upgrades-from FriendPool`. Adds reserve accounting improvements / fee handling (see source and `FundsDeposited` flow). |
| V3 | `FriendPoolV3.sol` | `@custom:oz-upgrades-from` `FriendPoolV2`. Adds **`transferFundsPartialyToRoom`**: dispatcher or owner can send a partial reserve draw to an arbitrary destination while routing an explicit **top-up fee** slice to the dev fee destination from `FriendKey`. |

### FriendRoomManager

| Line | Contract | Changes (high level) |
|------|----------|----------------------|
| V1 | `FriendRoomManager.sol` | Fees, pause, per-tier room registration rules. |
| V2 | `FriendRoomManagerV2.sol` | `@custom:oz-upgrades-from FriendRoomManager`. Adds **`maxRoomsPerType`** and **`creatorTotalRoomCount`**: caps **total** rooms per `RoomType` across tiers (used for Social limits); extends registration checks. |

### FriendStake (beacon implementation)

Trading pools use **BeaconProxy** clones; upgrading **one beacon** updates **all** stake pools.

| Line | Contract | Changes (high level) |
|------|----------|----------------------|
| V1 | `FriendStake.sol` | Stake / unstake / lock / batched rewards / `bridgeFee` in `initialize` (default from decimals if zero). |
| V2 | `FriendStakeV2.sol` | `@custom:oz-upgrades-from FriendStake`. Reward rounds, `DistributeFeeSent`, performance splits on `lockStaking`, iterable stake map. |
| V3 | `FriendStakeV3.sol` | `@custom:oz-upgrades-from FriendStake`. Same overall behavior as V2 for lock / distribute; **`initialize` sets `bridgeFee` to a fixed `100000`** (6-decimal USDC-style units) instead of deriving from `_bridgeFee` / token decimals. |

## Proxies / beacons referenced in upgrade scripts

Addresses are taken from `script/**` as of this branch. **Prod** and **preprod** rows reflect which constant is uncommented or labeled in each script; your deployer may use a different constant when running forge.

| Component | Role | Prod (script label) | Preprod / staging (script label) |
|-----------|------|----------------------|-----------------------------------|
| FriendKey | UUPS proxy | *(no prod constant in `FriendKeyUpgrade.s.sol` — verify mainnet proxy)* | `0xdfD77610dd30A21385b1B4C3AA6D20069624F792` |
| FriendPool | UUPS proxy | `0xa1bf9bb17C283CF17F01516f78f3127D2C84C79d` | `0xE0419931d9bCB71F4e529562Cc51a8cd8C3ed1AA` (commented in script) |
| FriendRoomManager | UUPS proxy | `0xbF4E9bF4aefBbA62bA1964fD70f69581bA9691d8` | `0x85f77d7D29e3f641CCdA8AC47c599A97738041B9` (commented) |
| FriendStake | **Beacon** (not a proxy) | `0x53BdEfB3E2faEB90b766B459AF96F3E357D3c3f9` (commented) | `0x2e03f3b2C0845b3b9e7B63E55280D93C1577D634` |

### Answering “what is live?” (prod vs preprod)

- **FriendKey — V1 or V2?** Preprod upgrade script targets **V2** (`FriendKeyV2.sol`) at `0xdfD7…`. **Prod** is not set in that script; confirm the mainnet proxy’s implementation — if that upgrade was not executed, prod remains **V1**.
- **FriendPool — V2 or V3?** Upgrade script points at **V3** for the prod proxy `0xa1bf…`. If that transaction was executed on prod, prod is **V3** (possibly via **V2** as an intermediate implementation history).
- **FriendRoomManager — V1 or V2?** Prod script upgrades `0xbF4E…` to **`FriendRoomManagerV2`**. If executed, prod is **V2**.
- **FriendStake — V2 or V3?** Stake uses a **beacon**; upgrades must use **`upgradeBeacon`**, not `upgradeProxy`. If the beacon was upgraded to **`FriendStakeV3`**, new clone logic uses V3’s `initialize` / default `bridgeFee`; confirm beacon implementation on-chain for prod vs preprod.

## Broadcast artifacts

Forge `broadcast/` JSON traces are **not** required for building or testing. This repo may ignore them so PRs stay reviewable; if you need a permanent audit trail, commit broadcast outputs in a **separate** branch or PR.
