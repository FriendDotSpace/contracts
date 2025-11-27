// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendPool} from "src/FriendPool.sol";
import {FriendUSD} from "src/FriendUSD.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title Deploy
 * @notice Comprehensive deployment script
 * @dev This script deploys:
 *      1. FriendUSD (if USDC address is not provided or is address(0))
 *      2. FriendStake beacon (used by FriendKey to create staking pools)
 *      3. FriendRoomManager UUPS proxy (main protocol contract)
 *      4. FriendKey UUPS proxy (main protocol contract)
 *      5. FriendPool UUPS proxy (cross-chain pool for bonding curve reserves)
 *      6. Configures FriendRoomManager to use FriendPool as trading pool fee destination
 */
contract Deploy is Script {
    // Configuration parameters
    uint16 constant DEV_FEE_PERCENT = 200; // 2%
    uint16 constant CREATOR_FEE_PERCENT = 200; // 2%
    uint16 constant TRADING_POOL_FEE_PERCENT = 600; // 6%
    uint16 constant DEV_PERFORMANCE_FEE_PERCENT = 500; // 5%
    uint16 constant CREATOR_PERFORMANCE_FEE_PERCENT = 1500; // 15%

    uint16 constant DEV_SOCIAL_FEE_PERCENT = 200; // 2%
    uint16 constant CREATOR_SOCIAL_FEE_PERCENT = 200; // 2%

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
        console2.log("Deploying FriendRoomManager...");

        // Deploy FriendRoomManager first
        bytes memory roomManagerInitData = abi.encodeCall(FriendRoomManager.initialize, (initialOwner));

        address roomManagerProxy = Upgrades.deployUUPSProxy("FriendRoomManager.sol", roomManagerInitData);
        FriendRoomManager roomManager = FriendRoomManager(roomManagerProxy);
        console2.log("FriendRoomManager deployed to:", address(roomManager));

        console2.log("Deploying FriendKey...");

        // Deploy FriendKey with RoomManager address
        bytes memory friendKeyInitData =
            abi.encodeCall(FriendKey.initialize, (initialOwner, bondingToken, friendStakeBeacon, address(roomManager)));

        address friendKeyProxy = Upgrades.deployUUPSProxy("FriendKey.sol", friendKeyInitData);
        FriendKey friendKey = FriendKey(friendKeyProxy);
        console2.log("FriendKey deployed to:", address(friendKey));
        friendKey.setSignee(SIGNEE);
        console2.log("Signee set to:", SIGNEE);

        // Set FriendKey address in RoomManager
        roomManager.setFriendKey(address(friendKey));
        // check if fees are different than default fees that are set, if different, set them or else skip
        (uint16 devFee, uint16 creatorFee, uint16 poolFee) = roomManager.getTradingFees();
        if (devFee != DEV_FEE_PERCENT || creatorFee != CREATOR_FEE_PERCENT || poolFee != TRADING_POOL_FEE_PERCENT) {
            roomManager.setTradingFees(DEV_FEE_PERCENT, CREATOR_FEE_PERCENT, TRADING_POOL_FEE_PERCENT);
            console2.log("Trading fees set in RoomManager");
        }
        (uint16 devPerformanceFee, uint16 creatorPerformanceFee) = roomManager.getPerformanceFees();
        if (
            devPerformanceFee != DEV_PERFORMANCE_FEE_PERCENT || creatorPerformanceFee != CREATOR_PERFORMANCE_FEE_PERCENT
        ) {
            roomManager.setPerformanceFees(DEV_PERFORMANCE_FEE_PERCENT, CREATOR_PERFORMANCE_FEE_PERCENT);
            console2.log("Performance fees set in RoomManager");
        }
        (uint16 devSocialFee, uint16 creatorSocialFee) = roomManager.getSocialFees();
        if (devSocialFee != DEV_SOCIAL_FEE_PERCENT || creatorSocialFee != CREATOR_SOCIAL_FEE_PERCENT) {
            roomManager.setSocialFees(DEV_SOCIAL_FEE_PERCENT, CREATOR_SOCIAL_FEE_PERCENT);
            console2.log("Social fees set in RoomManager");
        }

        // Set authority and eligibility duration in RoomManager
        uint256 eligibilityDuration = roomManager.eligibilityDuration();
        if (eligibilityDuration != ELIGIBILITY_DURATION) {
            roomManager.setEligibilityDuration(ELIGIBILITY_DURATION);
            console2.log("Eligibility duration set in RoomManager");
        }

        roomManager.setAuthority(authorityAddress);
        console2.log("Authority and eligibility duration set in RoomManager");

        // ============================================
        // 4. Deploy FriendPool (UUPS Proxy)
        // ============================================
        console2.log("Deploying FriendPool...");

        bytes memory friendPoolInitData =
            abi.encodeCall(FriendPool.initialize, (initialOwner, address(friendKey), dlnSourceAddress));

        address friendPoolProxy = Upgrades.deployUUPSProxy("FriendPool.sol", friendPoolInitData);
        FriendPool friendPool = FriendPool(friendPoolProxy);
        console2.log("FriendPool deployed to:", address(friendPool));

        // Now set fee destinations in RoomManager
        roomManager.setFeeDestinations(initialOwner, address(friendPool));
        console2.log("Fee destinations set in RoomManager (dev: owner, pool: FriendPool)");

        // ============================================
        // 5. Configure FriendPool
        // ============================================
        console2.log("Configuring FriendPool...");
        friendPool.setDispatcher(authorityAddress);
        console2.log("FriendPool dispatcher set to:", authorityAddress);
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
