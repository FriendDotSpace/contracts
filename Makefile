.PHONY: help deploy deploy-testnet deploy-mainnet verify clean test

# Default target
help:
	@echo "Friend.space Contracts - Deployment Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make deploy              - Deploy all contracts to prod (mainnet)"
	@echo "  make deploy-testnet      - Deploy to testnet (Base Sepolia)"
	@echo "  make deploy-mainnet      - Deploy to mainnet with safety delay"
	@echo "  make deploy-local        - Deploy to local network (Anvil)"
	@echo "  make simulate            - Simulate deployment without broadcasting"
	@echo "  make simulate-testnet    - Simulate testnet deployment"
	@echo "  make deploy-fusdc        - Deploy only FriendUSD"
	@echo "  make deploy-friendkey    - Deploy only FriendKey"
	@echo "  make deploy-friendpool   - Deploy only FriendPool"
	@echo "  make test                - Run tests"
	@echo "  make verify              - Verify deployed contracts"
	@echo "  make clean               - Clean build artifacts"
	@echo ""
	@echo "RPC Endpoints (from foundry.toml):"
	@echo "  prod                     - Production/Mainnet (uses RPC_URL env var)"
	@echo "  testnet                  - Testnet (uses TEST_RPC_URL env var)"
	@echo "  local                    - Local network (uses LOCAL_RPC_URL env var)"
	@echo ""
	@echo ""

# Main deployment target - deploys entire protocol
# Uses named RPC endpoint from foundry.toml [rpc_endpoints] section
deploy:
	@echo "Deploying All Contracts..."
	forge script script/Deploy.s.sol:Deploy --rpc-url prod --broadcast --verify -vvvv

# Deploy to testnet (Base Sepolia)
# Uses 'testnet' endpoint from foundry.toml
deploy-testnet:
	@echo "Deploying to Base Sepolia testnet..."
	forge script script/Deploy.s.sol:Deploy --rpc-url testnet --broadcast --verify -vvvv

# Deploy to mainnet (Base)
# Uses 'prod' endpoint from foundry.toml
deploy-mainnet:
	@echo "Deploying to MAINNET (Base)"
	@echo "Press Ctrl+C within 5 seconds to cancel..."
	@sleep 5
	forge script script/Deploy.s.sol:Deploy --rpc-url prod --broadcast --verify -vvvv

# Deploy to local network (e.g., Anvil)
# Uses 'local' endpoint from foundry.toml
deploy-local:
	@echo "Deploying to local network..."
	forge script script/Deploy.s.sol:Deploy --rpc-url local --broadcast -vvvv

# Deploy only FriendUSD
deploy-fusdc:
	@echo "Deploying FriendUSD..."
	forge script script/FriendToken.s.sol:FriendTokenScript --rpc-url prod --broadcast --verify -vvvv

# Deploy only FriendKey (using existing script)
deploy-friendkey:
	@echo "Deploying FriendKey..."
	forge script script/FriendKey.s.sol:FriendKeyScript --rpc-url testnet --broadcast --verify -vvvv

# Deploy only FriendPool (using existing script)
deploy-friendpool:
	@echo "Deploying FriendPool..."
	forge script script/FriendPool.s.sol:FriendPoolScript --rpc-url testnet --broadcast --verify -vvvv

# Simulate deployment without broadcasting (uses prod endpoint)
simulate:
	@echo "Simulating deployment..."
	forge script script/Deploy.s.sol:Deploy --rpc-url prod -vvv

# Simulate deployment on testnet
simulate-testnet:
	@echo "Simulating testnet deployment..."
	forge script script/Deploy.s.sol:Deploy --rpc-url testnet -vvv

# Run tests
test:
	make clean
	@echo "Running tests..."
	forge test -vv

# Run tests with gas reporting
test-gas:
	@echo "Running tests with gas reporting..."
	forge test --gas-report

# Run test coverage
coverage:
	@echo "Running test coverage..."
	forge coverage --ir-minimum

# Run test flow
test-flow:
	@echo "Running test flow..."
	forge script script/TestFlow.s.sol:TestFlowScript --rpc-url testnet --broadcast -vvv
# Verify contracts on Etherscan
verify:
	@echo "Verifying contracts..."
	@echo "Note: You'll need to manually verify each contract using the deployment addresses"
	@echo "Use: forge verify-contract <address> <contract> --chain-id <chain-id> --etherscan-api-key <key>"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	forge clean
	rm -rf cache out

# Build contracts
build:
	@echo "Building contracts..."
	forge build

# Format code
format:
	@echo "Formatting code..."
	forge fmt

# Check code formatting
format-check:
	@echo "Checking code formatting..."
	forge fmt --check

# Run slither static analysis
slither:
	@echo "Running Slither static analysis..."
	slither .

# Install dependencies
install:
	@echo "Installing dependencies..."
	forge install

# Update dependencies
update:
	@echo "Updating dependencies..."
	forge update

# Display contract sizes
sizes:
	@echo "Contract sizes:"
	forge build --sizes

