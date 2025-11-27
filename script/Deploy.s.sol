// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendPool} from "src/FriendPool.sol";
import {FriendUSD} from "src/FriendUSD.sol";

/**
 * @title Deploy
 * @notice Comprehensive deployment script
 * @dev This script deploys:
 *      1. FriendUSD (if USDC address is not provided or is address(0))
 *      2. FriendStake beacon (used by FriendKey to create staking pools)
 *      3. FriendKey UUPS proxy (main protocol contract)
 *      4. FriendPool UUPS proxy (cross-chain pool for bonding curve reserves)
 *      5. Configures FriendKey to use FriendPool as trading pool fee destination
 */
contract Deploy is Script {
    // Configuration parameters
    uint256 constant DEV_FEE_PERCENT = 200; // 2%
    uint256 constant CREATOR_FEE_PERCENT = 200; // 2%
    uint256 constant TRADING_POOL_FEE_PERCENT = 600; // 6%
    uint256 constant DEV_PERFORMANCE_FEE_PERCENT = 500; // 5%
    uint256 constant CREATOR_PERFORMANCE_FEE_PERCENT = 1500; // 15%
    uint256 constant ELIGIBILITY_DURATION = 1 days;
    address constant SIGNEE = 0x96b4A9c744F813a40b6a4D2B8EC0040E8EC4B788;
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.addr(deployerPrivateKey);

        // Optional: Get USDC address from environment variable
        // If not set or is address(0), we'll deploy FriendUSD
        address usdcAddress = vm.envOr("USDC_ADDRESS", address(0));

        // Optional: Get authority address from environment variable
        // If not set, use the deployer address
        address authorityAddress = vm.envOr("AUTHORITY_ADDRESS", initialOwner);

        // REQUIRED: Get DLN Source address from environment variable
        // Script will revert with error if DLN_SOURCE_ADDRESS is not set
        address dlnSourceAddress = vm.envAddress("DLN_SOURCE_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Starting Friend.space Protocol Deployment ===");
        console2.log("Deployer:", initialOwner);
        console2.log("");

        // ============================================
        // 1. Deploy or use existing bonding token (USDC/FriendUSD)
        // ============================================
        address bondingToken;
        if (usdcAddress == address(0)) {
            console2.log("Deploying FriendUSD (FUSDC)...");
            FriendUSD friendUSD = new FriendUSD(initialOwner);
            bondingToken = address(friendUSD);
            console2.log("FriendUSD deployed to:", bondingToken);
        } else {
            bondingToken = usdcAddress;
            console2.log("Using existing USDC at:", bondingToken);
        }
        console2.log("");

        // ============================================
        // 2. Deploy FriendStake Beacon
        // ============================================
        console2.log("Deploying FriendStake Beacon...");
        address friendStakeBeacon = Upgrades.deployBeacon("FriendStake.sol", initialOwner);
        console2.log("FriendStake Beacon deployed to:", friendStakeBeacon);
        console2.log("");

        // ============================================
        // 3. Deploy FriendKey (UUPS Proxy)
        // ============================================
        console2.log("Deploying FriendKey...");

        // Note: We use address(0) as temporary tradingPoolFeeDestination
        // We'll update it after deploying FriendPool
        bytes memory friendKeyInitData = abi.encodeCall(
            FriendKey.initialize,
            (
                initialOwner,
                initialOwner, // devFeeDestination (using deployer initially)
                DEV_FEE_PERCENT,
                CREATOR_FEE_PERCENT,
                address(0), // tradingPoolFeeDestination (will be set to FriendPool later)
                TRADING_POOL_FEE_PERCENT,
                DEV_PERFORMANCE_FEE_PERCENT,
                CREATOR_PERFORMANCE_FEE_PERCENT,
                bondingToken,
                friendStakeBeacon,
                authorityAddress,
                ELIGIBILITY_DURATION
            )
        );

        address friendKeyProxy = Upgrades.deployUUPSProxy("FriendKey.sol", friendKeyInitData);
        FriendKey friendKey = FriendKey(friendKeyProxy);
        console2.log("FriendKey deployed to:", address(friendKey));
        friendKey.setSignee(SIGNEE);
        console2.log("Signee set to:", SIGNEE);
        console2.log("");

        // ============================================
        // 4. Deploy FriendPool (UUPS Proxy)
        // ============================================
        console2.log("Deploying FriendPool...");

        bytes memory friendPoolInitData =
            abi.encodeCall(FriendPool.initialize, (initialOwner, address(friendKey), dlnSourceAddress));

        address friendPoolProxy = Upgrades.deployUUPSProxy("FriendPool.sol", friendPoolInitData);
        FriendPool friendPool = FriendPool(friendPoolProxy);
        console2.log("FriendPool deployed to:", address(friendPool));
        console2.log("");

        // ============================================
        // 5. Configure FriendKey to use FriendPool
        // ============================================
        console2.log("Configuring FriendKey to use FriendPool...");
        friendKey.setTradingPoolFeeDestination(address(friendPool));
        console2.log("Trading pool fee destination set to FriendPool");
        friendPool.setDispatcher(authorityAddress);
        console2.log("");

        // ============================================
        // Deployment Summary
        // ============================================
        console2.log("=== Deployment Summary ===");
        console2.log("Bonding Token:", bondingToken);
        console2.log("FriendStake Beacon:", friendStakeBeacon);
        console2.log("FriendKey Proxy:", address(friendKey));
        console2.log("FriendPool Proxy:", address(friendPool));
        console2.log("DLN Source:", dlnSourceAddress);
        console2.log("Authority:", authorityAddress);
        console2.log("");
        console2.log("=== Configuration ===");
        console2.log("Dev Fee: %s bps (%s%%)", DEV_FEE_PERCENT, DEV_FEE_PERCENT / 100);
        console2.log("Creator Fee: %s bps (%s%%)", CREATOR_FEE_PERCENT, CREATOR_FEE_PERCENT / 100);
        console2.log("Trading Pool Fee: %s bps (%s%%)", TRADING_POOL_FEE_PERCENT, TRADING_POOL_FEE_PERCENT / 100);
        console2.log(
            "Dev Performance Fee: %s bps (%s%%)", DEV_PERFORMANCE_FEE_PERCENT, DEV_PERFORMANCE_FEE_PERCENT / 100
        );
        console2.log(
            "Creator Performance Fee: %s bps (%s%%)",
            CREATOR_PERFORMANCE_FEE_PERCENT,
            CREATOR_PERFORMANCE_FEE_PERCENT / 100
        );
        console2.log("Eligibility Duration: %s days", ELIGIBILITY_DURATION / 1 days);
        console2.log("");
        console2.log("=== Deployment Complete ===");

        vm.stopBroadcast();
    }
}
