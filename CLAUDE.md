# contracts

Solidity smart contract suite for the FriendKey social token platform — ERC-1155 tokenized shares with bonding curve pricing, staking, and cross-chain operations on Base blockchain.

## Stack
- Solidity ^0.8.27, Foundry
- OpenZeppelin Contracts Upgradeable v5
- ERC-1155 multi-token standard
- UUPS + Beacon proxy patterns
- deBridge DLN for cross-chain

## Setup
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && ~/.foundry/bin/foundryup

# Install dependencies (git submodules)
forge install
# or
make install
```

## Commands
```bash
forge build                          # Compile
forge build --sizes --via-ir         # Build with size report (CI mode)
forge test -vv                       # Run tests
forge test --gas-report              # Tests with gas report
forge coverage --ir-minimum          # Coverage report
forge fmt                            # Format code
forge fmt --check                    # Check formatting (CI)

make test                            # forge test -vv
make test-gas                        # forge test --gas-report
make coverage                        # Coverage
make format                          # forge fmt
make format-check                    # forge fmt --check
make deploy-testnet                  # Deploy to Base Sepolia
make deploy-mainnet                  # Deploy to Base mainnet
make deploy-local                    # Deploy to local Anvil
make simulate                        # Dry-run deployment
make slither                         # Static analysis
```

## Environment Variables (`.env`)
```bash
PRIVATE_KEY=0x...
RPC_URL=https://mainnet.base.org        # Base mainnet
TEST_RPC_URL=https://sepolia.base.org   # Base Sepolia
LOCAL_RPC_URL=http://localhost:8545
USDC_ADDRESS=                           # Leave empty to deploy FriendUSD
DLN_SOURCE_ADDRESS=                     # Required for FriendPool
AUTHORITY_ADDRESS=                      # Defaults to deployer
ETHERSCAN_API_KEY=
```

## Contract Architecture
```
src/
├── FriendKey.sol          # Core ERC-1155 token contract (36KB)
├── FriendStake.sol        # Per-creator staking/rewards (20KB)
├── FriendPool.sol         # Cross-chain pool management (11KB)
├── FriendRoomManager.sol  # Room limits & fee config (19KB)
├── FriendUSD.sol          # Mock USDC for testing
├── interfaces/            # IFriendKey, IFriendPool, IFriendRoomManager, IDlnSource
├── libraries/
│   ├── BondingCurveLib.sol  # Polynomial pricing: price = (sum_of_squares * unit) / divisor
│   ├── DlnOrderLib.sol      # Cross-chain order structures
│   └── Errors.sol           # Custom error definitions
└── mocks/                 # MockBridge, MockPool for tests
```

## Key Concepts
- **Room tiers**: Casual (divisor 4000), Club (40), Exclusive (4) — affects bonding curve pricing
- **Room types**: Trading (full features) vs Social (no staking/pool)
- **Proxy pattern**: UUPS for FriendKey/FriendPool/FriendRoomManager; Beacon for FriendStake (per-creator instances)
- **Creator registration**: requires EIP-712 signature from authority address
- **Fee split**: Dev fee (2%) + Creator fee (2%) + Trading pool fee (6%)

## Deployment Order (handled by `Deploy.s.sol`)
1. FriendUSD (if USDC not provided)
2. FriendStake Beacon
3. FriendRoomManager (UUPS Proxy)
4. FriendKey (UUPS Proxy)
5. FriendPool (UUPS Proxy)

## CI/CD
GitHub Actions (`.github/workflows/test.yml`): fmt check → build → test (all with `--via-ir`)
