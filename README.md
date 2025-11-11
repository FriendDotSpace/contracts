# FriendKey Social Token Platform

FriendKey is a social token platform built on Ethereum that allows creators to issue their own tokenized social shares using a bonding curve mechanism. Users can buy and sell shares associated with creators, creating a social marketplace with economic incentives.

## Project Overview

This project implements an ERC-1155 based token contract with the following key features:

- **Bonding Curve Pricing**: Token prices are determined by a bonding curve that increases with supply
- **Creator Shares**: Each creator has a unique token ID representing their "shares"
- **Fee Structure**: Includes dev fees, creator fees, and trading pool fees
- **Upgradeable Contract**: Uses the UUPS proxy pattern for future upgrades

## Contract Architecture

The project consists of three main contracts:

### FriendKey
The main contract that inherits from several OpenZeppelin contracts:

- `ERC1155Upgradeable`: Base token standard
- `ERC1155BurnableUpgradeable`: Allows tokens to be burned
- `ERC1155SupplyUpgradeable`: Tracks token supply
- `OwnableUpgradeable`: Access control
- `UUPSUpgradeable`: Upgradeable proxy pattern

### FriendStake
A staking contract that allows users to stake their FriendKey tokens to earn rewards:

- **Token Staking**: Users can stake their FriendKey tokens for specific creators
- **Reward Distribution**: Distributes rewards to stakers based on their stake
- **Lock Mechanism**: Supports time-locked staking periods
- **Upgradeable**: Uses OpenZeppelin's upgradeable contracts pattern

### FriendPool
A pool contract that manages reserves and cross-chain functionality:

- **Reserve Management**: Manages bonding curve reserves for each creator
- **Cross-chain Integration**: Integrates with DLN (deBridge Liquidity Network) for cross-chain operations
- **Fund Dispatching**: Allows authorized dispatching of funds across chains
- **Upgradeable**: Uses UUPS proxy pattern for future upgrades

## Key Functions

### FriendKey Contract
- `buyShares(address creatorAddress, uint256 amount)`: Purchase shares of a creator
- `sellShares(address creatorAddress, uint256 amount)`: Sell shares of a creator
- `getBuyPrice(uint256 id, uint256 amount)`: Calculate purchase price before fees
- `getSellPrice(uint256 id, uint256 amount)`: Calculate sell price before fees
- `registerCreator(string metadata, bytes signature)`: Register as a creator (requires owner-signed authorization) and attach an off-chain metadata pointer (e.g., hash or URI)

### FriendStake Contract
- `stake(uint256 amount)`: Stake FriendKey tokens to earn rewards
- `unstake(uint256 amount)`: Unstake tokens after lock period
- `claimReward()`: Claim earned rewards from staking
- `setReward(uint256 amount)`: Set reward amount for distribution (owner only)

### FriendPool Contract
- `pull(uint256 tokenId, uint256 amount)`: Pull funds from bonding curve reserves
- `dispatch(uint256 tokenId, uint256 amount)`: Dispatch funds cross-chain using DLN
- `allowDispatch(uint256 tokenId, address recipient)`: Authorize fund dispatching

### Mock Contracts
- `MockPool`: A mock contract for testing the pool functionality
- `MockBridge`: A mock contract for testing cross-chain operations

> [!NOTE]
> Mock bridge should mimic the interface of the real bridge contract to ensure compatibility during testing. It should send fund to the owner address.

## Installation and Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js & npm/yarn

### Installing Foundry

See [Foundry installation guide](https://book.getfoundry.sh/getting-started/installation).

### Initializing the project

```bash
forge build
```

> [!TIP]
> If you get random errors try `forge clean` and `forge build` again.

## Development

### Testing the contract

```bash
forge test --force
```

### Deployment

> [!IMPORTANT]
> Make sure to set up your environment variables (`.env`) before deploying.

#### Environment Variables

```bash
# Required
PRIVATE_KEY=0x<PRIVATE_KEY>

# Network RPC URLs
TEST_RPC_URL=https://sepolia.base.org
RPC_URL=https://mainnet.base.org

# Optional - Protocol Configuration
USDC_ADDRESS=0x...                    # If not set or address(0), FriendUSD will be deployed
DLN_SOURCE_ADDRESS=0x...              # Required for FriendPool deployment
AUTHORITY_ADDRESS=0x...               # If not set, deployer address will be used
ETHERSCAN_API_KEY=your_api_key       # For contract verification (only add if you want to verify, else skip)
```

#### Comprehensive Deployment (Recommended)

The `Deploy.s.sol` script provides a comprehensive deployment that:
1. Deploys FriendUSD (if USDC address not provided)
2. Deploys FriendStake beacon
3. Deploys FriendKey proxy
4. Deploys FriendPool proxy
5. Configures FriendKey to use FriendPool

**Using Makefile (Easiest):**

```bash
# Deploy everything to testnet
make deploy-testnet

# Deploy everything to mainnet (with 5s safety delay)
make deploy-mainnet

# Simulate deployment without broadcasting
make simulate
```

**Using Forge Script Directly:**

```bash
# Simulate deployment
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL -vvvv

# Deploy to testnet
forge script script/Deploy.s.sol:Deploy --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv

# Deploy to mainnet
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
```

> [!TIP]
> If you get an error `Failed to get EIP-1559 fees`
> you have to use `--legacy` flag [source](https://ethereum.stackexchange.com/questions/147942/failed-to-get-eip-1559-fees-error-when-deploying-to-zkevm-polygon-using-foundry)


FriendKey is an UUPS [upgradable smart contract](https://docs.openzeppelin.com/upgrades-plugins/).
In order to run some checks about upgradability, previous version of contract is required and
`@custom:oz-upgrades-from <reference>` annotation in new version.
After deployment of one version, the file has to remain unchanged to verify upgradability to the next version.
It is recommended to create a new file for the next version.

To check upgradability run
```bash
npx @openzeppelin/upgrades-core validate
```

## Technical Details

### Bonding Curve

The bonding curve follows a polynomial formula that ensures price increases with supply. The curve is defined by:

```
price = (summation) * bondingTokenPriceUnit / 16000
```

Where summation is calculated based on supply and amount.

### Fee Structure

Three types of fees are applied to transactions:
- Developer fee: Sent to a designated address
- Creator fee: Accumulated for the creator to claim
- Trading pool fee: Sent to a designated address for ecosystem incentives

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Dev hacks

### Proper file import in VSCode

To ensure proper file import in VSCode, add the following to your `.vscode`:

```json
{
  "solidity.packageDefaultDependenciesContractsDirectory": "src",
  "solidity.packageDefaultDependenciesDirectory": "lib",
  "solidity.compileUsingRemoteVersion": "v0.8.27",
  "solidity.remappings": [
    "@openzeppelin/contracts/=lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/",
    "@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/",
    "forge-std/=lib/forge-std/src/",
    "openzeppelin-foundry-upgrades/=lib/openzeppelin-foundry-upgrades/src/"
  ]
}
```
