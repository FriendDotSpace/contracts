# contracts

FriendKey Solidity contracts — ERC-1155 creator shares with bonding curve, staking, cross-chain on Base. Foundry + OpenZeppelin upgradeable v5, Solidity ^0.8.27.

## Setup & commands

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup   # one-time
forge install                                              # submodule deps

forge build --via-ir
forge test -vv                 # or: make test
forge test --gas-report
forge coverage --ir-minimum
forge fmt --check
make slither                   # static analysis

make deploy-testnet | deploy-mainnet | deploy-local
make simulate                  # dry-run
```

## Env (`.env`)

`PRIVATE_KEY`, `RPC_URL` (Base mainnet), `TEST_RPC_URL` (Sepolia), `LOCAL_RPC_URL`, `USDC_ADDRESS` (empty → deploy FriendUSD), `DLN_SOURCE_ADDRESS` (for FriendPool), `AUTHORITY_ADDRESS` (defaults to deployer), `ETHERSCAN_API_KEY`.

## Contracts

- `FriendKey` — ERC-1155 shares + bonding curve (UUPS)
- `FriendStake` — per-creator staking/rewards (Beacon proxy, per-creator instance)
- `FriendPool` — cross-chain reserves via deBridge DLN (UUPS)
- `FriendRoomManager` — fees + room-creation limits (UUPS)
- `FriendUSD` — mock USDC for local testing
- `libraries/BondingCurveLib.sol` — `price = (sum_of_squares * unit) / divisor`

## Concepts

- **Tiers** (bonding-curve divisor): Casual 4000, Club 40, Exclusive 4
- **Types**: Trading (full) vs Social (no stake/pool)
- **Creator registration**: requires EIP-712 signature from authority
- **Fee split**: dev 2% + creator 2% + trading pool 6%
- **Deploy order** (see `script/Deploy.s.sol`): FriendUSD → StakeBeacon → RoomManager → FriendKey → FriendPool
