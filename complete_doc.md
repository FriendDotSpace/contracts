# FriendKey Developer Documentation

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Contract Interactions](#contract-interactions)
3. [Room Types & Tiers](#room-types--tiers)
4. [Bonding Curve Mechanics](#bonding-curve-mechanics)
5. [Fee Structure](#fee-structure)
6. [Upgradeability](#upgradeability)
7. [Testing Guide](#testing-guide)
8. [Deployment Guide](#deployment-guide)
9. [Integration Guide](#integration-guide)

---

## Contract Connections & Flow 

### note: FriendRoomMananger handles the fee part and admin/dev functionalities only, so not included below

```
                         ┌──────────────┐
                         │    USERS     │
                         └──────┬───────┘
                                │
                    ┌───────────┼───────────┐
                    │           │           │
              ┌─────▼────┐ ┌───▼────┐ ┌───▼────┐
              │ Register │ │  Buy   │ │  Sell  │
              │ Creator  │ │ Shares │ │ Shares │
              └─────┬────┘ └───┬────┘ └───┬────┘
                    │          │          │
                    └──────────┼──────────┘
                               │
                      ┌────────▼─────────┐
                      │   FriendKey      │◄────────┐
                      │  (UUPS Proxy)    │         │
                      │                  │         │
                      │ • ERC1155 Tokens │         │
                      │ • Bonding Curve  │         │
                      │ • Fee Distribution│        │
                      └──┬───┬───┬───┬───┘         │
                         │   │   │   │             │
        ┌────────────────┘   │   │   └─────────────┤
        │                    │   │                 │
        │ creates      fees  │   │ queries    calls│
        │                    │   │                 │
    ┌───▼────────┐    ┌─────▼───▼─────┐   ┌───────┴────────┐
    │ FriendStake│    │   FriendPool   │   │   FriendUSD    │
    │BeaconProxies│◄───┤  (UUPS Proxy)  │   │   (USDC/ERC20) │
    │            │    │                │   │                │
    │ Creator #1 │    │ • Pool Fees    │   │ • Trading Token│
    │ Creator #2 │    │ • Cross-chain  │   │ • 6 decimals   │
    │ Creator #3 │    │ • DLN Bridge   │   └────────────────┘
    │ Creator #N │    └────────┬───────┘
    └────┬───────┘             │
         │                     │ dispatch
         │ rewards             │
         │                     ▼
         │              ┌──────────────┐
         │              │  DLN Source  │
         │              │ (deBridge)   │
         │              │              │
         │              │ Cross-chain  │
         └──────────────┤   Bridge     │
                        └──────────────┘
```

## Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                      FriendKey Ecosystem                     │
└─────────────────────────────────────────────────────────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        ▼                      ▼                      ▼
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│  FriendKey   │◄────►│RoomManager   │      │ FriendPool   │
│   (Core)     │      │  (Limits)    │      │ (Cross-chain)│
└──────┬───────┘      └──────────────┘      └──────────────┘
       │
       ├─────► FriendStake (per creator, Beacon Proxy, for trading rooms) 
       ├─────► BondingCurveLib (Library)
       └─────► ERC1155 Tokens (shares)
```

### Contract Responsibilities

| Contract | Primary Role | Key Features |
|----------|-------------|--------------|
| **FriendKey** | Core token logic | Buy/sell shares, register creators, staking interface |
| **FriendRoomManager** | Room limits & config | Fee management, room creation limits, bonding curve params |
| **FriendStake** | Staking rewards | Per-creator staking, reward distribution, eligibility tracking |
| **FriendPool** | Cross-chain ops | Reserve management, DLN integration, fund dispatching |
| **BondingCurveLib** | Price calculation | Pure math functions for bonding curve pricing |

---

## Contract Interactions

### User Flow: Registering a Creator

```mermaid
sequenceDiagram
    participant U as User
    participant FK as FriendKey
    participant RM as RoomManager
    participant FS as FriendStake
    
    U->>FK: registerCreator(tier, keys, metadata, sig)
    FK->>FK: Verify EIP-712 signature
    FK->>RM: checkAndUpdateRoomRegistration()
    RM->>RM: Check room limits
    alt Limit exceeded
        RM-->>FK: Revert: RoomLimitExceeded
    else Limit OK
        RM->>RM: Update room nonce
        RM-->>FK: Success
        FK->>FK: Mint token ID
        FK->>FS: Deploy Beacon Proxy (if Trading)
        FK->>FK: buyShares(1 + additionalKeys)
        FK-->>U: Return tokenId
    end
```

### User Flow: Buying Shares

```mermaid
sequenceDiagram
    participant U as User
    participant FK as FriendKey
    participant RM as RoomManager
    participant USDC as Bonding Token
    
    U->>FK: buyShares(tokenId, amount, maxSpend)
    FK->>RM: getTradingFees() or getSocialFees()
    RM-->>FK: Fee percentages
    FK->>FK: Calculate price + fees
    FK->>FK: Check slippage (totalCost <= maxSpend)
    FK->>USDC: transferFrom(user, totalCost)
    FK->>FK: _mint(user, tokenId, amount)
    FK->>USDC: Distribute fees (dev, creator, pool)
    FK-->>U: Emit Trade event
```

### User Flow: Staking

```mermaid
sequenceDiagram
    participant U as User
    participant FK as FriendKey
    participant FS as FriendStake
    
    U->>FK: stake(tokenId, amount)
    FK->>FS: Check isOpenForStaking()
    FK->>FS: safeTransferFrom(user, stakingPool, amount)
    FS->>FS: Update staked balances
    FS->>FK: Update keyHoldingSince
    FS-->>U: Tokens staked
```

---

## Room Types & Tiers

### Room Types

```solidity
enum RoomType {
    Trading,  // Full functionality: trading, staking, cross-chain
    Social    // Limited: chats only, no staking/pool
}
```

| Feature | Trading Rooms | Social Rooms |
|---------|--------------|--------------|
| Token Trading | ✅ | ✅ |
| Staking Pool | ✅ | ❌ |
| Trading Pool Fee | ✅ | ❌ 0 |
| Cross-chain | ✅ | ❌ |

### Room Tiers

```solidity
enum RoomTier {
    Casual,     // Divisor: 4000 (trading) / 8000 (social) - Lowest prices
    Club,       // Divisor: 40 (trading) / 80 (social) - Medium prices
    Exclusive   // Divisor: 4 (trading) / 8 (social) - Highest prices
}
```

**Price Impact**: Lower divisor = Higher prices = More exclusive

### Room Limits (Default Configuration)

```javascript
// Trading Rooms (per creator per tier)
maxRoomsPerTier[Trading][Casual] = 0;     // Disabled by default
maxRoomsPerTier[Trading][Club] = 1;       // 1 Club room allowed
maxRoomsPerTier[Trading][Exclusive] = 1;  // 1 Exclusive room allowed

// Social Rooms (per creator per tier)
maxRoomsPerTier[Social][Casual] = 0;      // Disabled by default
maxRoomsPerTier[Social][Club] = 0;        // Disabled by default
maxRoomsPerTier[Social][Exclusive] = 0;   // Disabled by default
```

**Note**: Limits can be changed by contract owner via `FriendRoomManager.setMaxRoomsPerTier()`

---

## Bonding Curve Mechanics

### Formula

The bonding curve uses a polynomial pricing model:

```javascript
price = (summation * bondingTokenPriceUnit) / divisor

where:
summation = sum of squares from (supply+1) to (supply+amount)
          = (supply * (supply + 1) * (2 * supply + 1)) / 6
          + (supply * amount)
          + (amount * (amount + 1) * (2 * amount + 1)) / 6
```

### Price Calculation Examples

**Example 1: First key purchase (Club tier, Trading)**
```javascript
supply = 0, amount = 1, divisor = 40
summation = (0 * 1 * 1) / 6 + (0 * 1) + (1 * 2 * 3) / 6 = 1
price = (1 * 1,000,000) / 40 = 25,000 USDC (0.025 USDC with 6 decimals)
```

**Example 2: Buying 10 keys when supply is 100**
```javascript
supply = 100, amount = 10, divisor = 40
summation ≈ 10,525
price = (10,525 * 1,000,000) / 40 = 263,125,000 (263.125 USDC)
```

### Divisor Impact (for e.g)

```
Tier        | Trading Divisor | Social Divisor | Price Ratio
------------|----------------|----------------|-------------
Casual      | 4000          | 8000          | 1x (baseline)
Club        | 40            | 80            | 100x
Exclusive   | 4             | 8             | 1000x
```

**If Social rooms have 2x higher divisors = 50% lower prices than trading rooms**

---

## Fee Structure

### Trading Rooms (Default Fees)

```javascript
devFeePercent = 200;              // 2% to dev address
creatorFeePercent = 200;          // 2% to creator
tradingPoolFeePercent = 600;      // 6% to trading pool
// Total: 10%

devPerformanceFeePercent = 500;   // 5% on staking rewards
creatorPerformanceFeePercent = 1500; // 15% on staking rewards
```

### Social Rooms (Default Fees)

```javascript
socialDevFeePercent = 200;        // 2% to dev address
socialCreatorFeePercent = 200;    // 2% to creator
// Total: 4%
// No trading pool fee (social rooms don't have pools)
```

### Fee Distribution Flow

```
Buy Transaction (Trading Room):
┌──────────────┐
│ User pays:   │
│ 100 USDC     │
└──────┬───────┘
       │
       ├─► 2 USDC  → Dev address
       ├─► 2 USDC  → Creator address
       ├─► 6 USDC  → Trading Pool (FriendPool)
       └─► 90 USDC → Bonding Curve Reserve
```

### Slippage Protection

```solidity
// Buy with maximum spend limit
buyShares(tokenId, 10, 100_000000); // Max 100 USDC
// Reverts if totalCost > 100 USDC

// Sell with minimum receive limit
sellShares(tokenId, 5, 50_000000); // Min 50 USDC
// Reverts if proceeds < 50 USDC
```

### Upgrade Process

1. **Deploy new implementation**:
   ```bash
   forge script script/FriendKeyUpgrade.s.sol --broadcast
   ```

2. **Validate upgrade safety**:
   ```bash
   npx @openzeppelin/upgrades-core validate
   ```

3. **Upgrade proxy**:
   ```solidity
   // Call upgradeToAndCall on the proxy
   proxy.upgradeToAndCall(newImplementation, initData);
   ```

### Upgrade Checklist

- [ ] Storage layout unchanged (no reordering, no type changes)
- [ ] New variables added only to the end
- [ ] Constructor is disabled (`_disableInitializers()`)
- [ ] Initializer used instead of constructor
- [ ] `_authorizeUpgrade` restricted to owner
- [ ] Tests pass for both old and new versions
- [ ] Upgrade safety validation passes

---

## Testing Guide

### Running Tests

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-contract FriendKeyTest

# Run specific test function
forge test --match-test testBuyShares

# Run with verbosity
forge test -vvv

# Run with gas reporting
forge test --gas-report
```

### Test Coverage

```bash
# Generate coverage report
forge coverage

# Generate detailed HTML coverage report
forge coverage --report lcov
genhtml lcov.info -o coverage
open coverage/index.html
```

## Resources

- **OpenZeppelin Upgrades**: https://docs.openzeppelin.com/upgrades-plugins/
- **Foundry Book**: https://book.getfoundry.sh/
- **EIP-712**: https://eips.ethereum.org/EIPS/eip-712
- **UUPS Pattern**: https://eips.ethereum.org/EIPS/eip-1822

---

**Version**: 1.0.0

