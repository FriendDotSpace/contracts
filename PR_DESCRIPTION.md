## Summary

Adds and wires **upgradeable implementations** (`FriendKeyV2`, `FriendPoolV2`/`FriendPoolV3`, `FriendRoomManagerV2`, `FriendStakeV2`/`FriendStakeV3`) plus scripts and **tests that exercise the deployed-shaped code paths**. **`broadcast/` transaction JSON is gitignored** so this PR is dominated by Solidity and tests, not artifact noise.

## Version / environment matrix

See **[DEPLOYMENT_VERSIONS.md](./DEPLOYMENT_VERSIONS.md)** for:

- What each **V2/V3** changes vs the prior line.
- **Proxy / beacon addresses** baked into `script/**` for **prod vs preprod**.
- Explicit caveats: **confirm live implementations on-chain** (UUPS implementation slot / beacon implementation) before claiming prod vs staging.

Quick answers (script-inferred; **verify on-chain**):

| Contract | Prod (if upgrades ran as scripted) | Preprod (script constants) |
|----------|-----------------------------------|-----------------------------|
| FriendKey | Confirm proxy impl | **V2** target `0xdfD7…` |
| FriendPool | **V3** target `0xa1bf…` | Alternate proxy in script comments |
| FriendRoomManager | **V2** target `0xbF4E…` | Alternate proxy in script comments |
| FriendStake | **Beacon** — use `upgradeBeacon` | Beacon `0x2e03…` in script |

## Tests

- `test/ProtocolV2V3.t.sol` — `FriendPoolV3.partial` transfer path, `FriendRoomManagerV2` upgrade + `maxRoomsPerType`, `FriendStakeV3` beacon + default `bridgeFee`.
- Tests pass `Options.unsafeSkipAllChecks` to OpenZeppelin Foundry Upgrades so local **`forge test`** works after incremental compiles; **`forge clean && forge build`** (as in CI) still exercises full bytecode validation when checks are enabled in scripts.

## Repo hygiene

- **`/broadcast/`** added to **`.gitignore`**; remove tracked broadcasts with `git rm -r --cached broadcast/` (done on branch if present).
- For auditability, commit forge broadcasts in a **follow-up PR** if desired.

## Merge / history

- Prefer **squashing** noisy commits into **one commit per logical change** (e.g. contracts + scripts, tests, chore/ignore/docs) before merging to `main`.
- If this branch was already pushed with rewritten history, coordinate a **force-push** with reviewers.
