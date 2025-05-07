# FriendKey Social Token Platform

FriendKey is a social token platform built on Ethereum that allows creators to issue their own tokenized social shares using a bonding curve mechanism. Users can buy and sell shares associated with creators, creating a social marketplace with economic incentives.

## Project Overview

This project implements an ERC-1155 based token contract with the following key features:

- **Bonding Curve Pricing**: Token prices are determined by a bonding curve that increases with supply
- **Creator Shares**: Each creator has a unique token ID representing their "shares"
- **Fee Structure**: Includes dev fees, creator fees, and trading pool fees
- **Upgradeable Contract**: Uses the UUPS proxy pattern for future upgrades

## Contract Architecture

The `FriendKey` contract inherits from several OpenZeppelin contracts:

- `ERC1155Upgradeable`: Base token standard
- `ERC1155BurnableUpgradeable`: Allows tokens to be burned
- `ERC1155SupplyUpgradeable`: Tracks token supply
- `OwnableUpgradeable`: Access control
- `UUPSUpgradeable`: Upgradeable proxy pattern

## Key Functions

- `buyShares(address creatorAddress, uint256 amount)`: Purchase shares of a creator
- `sellShares(address creatorAddress, uint256 amount)`: Sell shares of a creator
- `getBuyPrice(uint256 id, uint256 amount)`: Calculate purchase price before fees
- `getSellPrice(uint256 id, uint256 amount)`: Calculate sell price before fees

## Installation and Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js & npm/yarn

### Installing Foundry

See [Foundry installation guide](https://book.getfoundry.sh/getting-started/installation).

### Initializing the project

```
bash setup.sh
```

## Development

### Testing the contract

```
forge test --force
```

### Deployment

You can simulate a deployment by running the script:

```
forge script script/FriendKey.s.sol --force
```

To deploy to a real network, add your private key and API keys to a `.env` file, then run:

```
forge script script/FriendKey.s.sol --rpc-url <your_rpc_url> --broadcast --verify -vvvv
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

## Additional Resources

See [Solidity scripting guide](https://book.getfoundry.sh/guides/scripting-with-solidity) for more information on deploying with Foundry.
