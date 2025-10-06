// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// import {Script} from "forge-std/Script.sol";
// import {stdJson} from "forge-std/StdJson.sol";

// /**
//  * @title DeploymentConfig
//  * @notice Library for loading network-specific configuration and managing deployments
//  * @dev Provides utilities for reading config files and writing deployment results
//  */
// library DeploymentConfig {
//     using stdJson for string;

//     struct NetworkConfig {
//         string name;
//         uint256 chainId;
//         address usdc;
//         address dlnSource;
//         uint256 devFeePercent;
//         uint256 creatorFeePercent;
//         uint256 tradingPoolFeePercent;
//         uint256 devPerformanceFeePercent;
//         uint256 creatorPerformanceFeePercent;
//         address devFeeDestination;
//         address tradingPoolFeeDestination;
//         address[] faucetRecipients;
//         uint256 faucetAmount;
//         uint256 faucetTimes;
//     }

//     struct DeploymentResult {
//         string network;
//         uint256 chainId;
//         uint256 timestamp;
//         address friendKey;
//         address friendStake;
//         address friendPool;
//         address friendUSD;
//         address deployer;
//     }

//     /**
//      * @notice Loads network configuration from JSON file
//      * @param network The network name (e.g., "base-sepolia", "base-mainnet")
//      * @return config The loaded network configuration
//      */
//     function loadNetworkConfig(string memory network) internal view returns (NetworkConfig memory config) {
//         string memory configPath = string.concat("./config/", network, ".json");
//         string memory json = vm.readFile(configPath);

//         config.name = json.readString(".name");
//         config.chainId = json.readUint(".chainId");
//         config.usdc = json.readAddress(".contracts.usdc");
//         config.dlnSource = json.readAddress(".contracts.dlnSource");
//         config.devFeePercent = json.readUint(".parameters.devFeePercent");
//         config.creatorFeePercent = json.readUint(".parameters.creatorFeePercent");
//         config.tradingPoolFeePercent = json.readUint(".parameters.tradingPoolFeePercent");
//         config.devPerformanceFeePercent = json.readUint(".parameters.devPerformanceFeePercent");
//         config.creatorPerformanceFeePercent = json.readUint(".parameters.creatorPerformanceFeePercent");
//         config.devFeeDestination = json.readAddress(".addresses.devFeeDestination");
//         config.tradingPoolFeeDestination = json.readAddress(".addresses.tradingPoolFeeDestination");

//         // Handle faucet configuration
//         try json.readUintArray(".faucet.recipients") returns (uint256[] memory recipientUints) {
//             config.faucetRecipients = new address[](recipientUints.length);
//             for (uint256 i = 0; i < recipientUints.length; i++) {
//                 config.faucetRecipients[i] = address(uint160(recipientUints[i]));
//             }
//         } catch {
//             // If reading as uint array fails, try reading as address array
//             try json.readAddressArray(".faucet.recipients") returns (address[] memory recipients) {
//                 config.faucetRecipients = recipients;
//             } catch {
//                 config.faucetRecipients = new address[](0);
//             }
//         }

//         config.faucetAmount = json.readUint(".faucet.amount");
//         config.faucetTimes = json.readUint(".faucet.times");
//     }

//     /**
//      * @notice Saves deployment results to JSON file
//      * @param network The network name
//      * @param result The deployment result to save
//      */
//     function saveDeploymentResult(string memory network, DeploymentResult memory result) internal {
//         string memory deploymentPath = string.concat("./deployments/", network, "/");

//         // Create directory if it doesn't exist (note: this might require manual creation in some environments)
//         string memory latestPath = string.concat(deploymentPath, "latest.json");
//         string memory timestampPath = string.concat(deploymentPath, vm.toString(result.timestamp), ".json");

//         string memory json = "deploymentResult";
//         vm.serializeString(json, "network", result.network);
//         vm.serializeUint(json, "chainId", result.chainId);
//         vm.serializeUint(json, "timestamp", result.timestamp);
//         vm.serializeAddress(json, "friendKey", result.friendKey);
//         vm.serializeAddress(json, "friendStake", result.friendStake);
//         vm.serializeAddress(json, "friendPool", result.friendPool);
//         vm.serializeAddress(json, "friendUSD", result.friendUSD);
//         string memory finalJson = vm.serializeAddress(json, "deployer", result.deployer);

//         // Write to both latest and timestamped files
//         vm.writeFile(latestPath, finalJson);
//         vm.writeFile(timestampPath, finalJson);
//     }

//     /**
//      * @notice Loads the latest deployment for a network
//      * @param network The network name
//      * @return result The latest deployment result
//      */
//     function loadLatestDeployment(string memory network) internal view returns (DeploymentResult memory result) {
//         string memory latestPath = string.concat("./deployments/", network, "/latest.json");
//         string memory json = vm.readFile(latestPath);

//         result.network = json.readString(".network");
//         result.chainId = json.readUint(".chainId");
//         result.timestamp = json.readUint(".timestamp");
//         result.friendKey = json.readAddress(".friendKey");
//         result.friendStake = json.readAddress(".friendStake");
//         result.friendPool = json.readAddress(".friendPool");
//         result.friendUSD = json.readAddress(".friendUSD");
//         result.deployer = json.readAddress(".deployer");
//     }

//     /**
//      * @notice Gets the current network name from environment or chain ID
//      * @return network The network name to use for configuration
//      */
//     function getCurrentNetwork() internal view returns (string memory network) {
//         // Try to get network from environment variable first
//         try vm.envString("NETWORK") returns (string memory envNetwork) {
//             return envNetwork;
//         } catch {
//             // Fall back to chain ID detection
//             uint256 chainId = block.chainid;
//             if (chainId == 84532) return "base-sepolia";
//             if (chainId == 8453) return "base-mainnet";
//             if (chainId == 1) return "ethereum-mainnet";
//             if (chainId == 31337) return "local";

//             // Default fallback
//             return "local";
//         }
//     }

//     /**
//      * @notice Validates that required addresses are not zero
//      * @param config The network configuration to validate
//      */
//     function validateConfig(NetworkConfig memory config) internal pure {
//         require(config.chainId != 0, "DeploymentConfig: Invalid chain ID");
//         require(config.devFeePercent + config.creatorFeePercent + config.tradingPoolFeePercent <= 10000,
//                 "DeploymentConfig: Total fee percentage exceeds 100%");
//     }
// }

// /**
//  * @title BaseDeploymentScript
//  * @notice Base contract for deployment scripts with configuration management
//  * @dev Provides common functionality for loading configs and saving results
//  */
// abstract contract BaseDeploymentScript is Script {
//     using DeploymentConfig for *;

//     DeploymentConfig.NetworkConfig internal config;
//     string internal currentNetwork;

//     modifier withConfig() {
//         currentNetwork = DeploymentConfig.getCurrentNetwork();
//         config = DeploymentConfig.loadNetworkConfig(currentNetwork);
//         DeploymentConfig.validateConfig(config);

//         // Override zero addresses with deployer if needed
//         address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
//         if (config.devFeeDestination == address(0)) {
//             config.devFeeDestination = deployer;
//         }
//         if (config.tradingPoolFeeDestination == address(0)) {
//             config.tradingPoolFeeDestination = deployer;
//         }

//         _;
//     }

//     /**
//      * @notice Saves deployment results
//      * @param result The deployment result to save
//      */
//     function saveResults(DeploymentConfig.DeploymentResult memory result) internal {
//         DeploymentConfig.saveDeploymentResult(currentNetwork, result);
//     }

//     /**
//      * @notice Loads the latest deployment for current network
//      * @return result The latest deployment result
//      */
//     function loadLatestDeployment() internal view returns (DeploymentConfig.DeploymentResult memory result) {
//         return DeploymentConfig.loadLatestDeployment(currentNetwork);
//     }
// }
