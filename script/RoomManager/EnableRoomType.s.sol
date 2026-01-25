// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";
import {IFriendKey} from "src/interfaces/IFriendKey.sol";

/**
 * @title EnableRoomTypeScript
 * @notice Enables a room type/tier with default limit (1) in RoomManager
 */
contract EnableRoomTypeScript is Script {
    // Update with deployed RoomManager proxy
    // address constant ROOM_MANAGER_PROXY = 0x4a31C071e797d8B818B67a80768e35EE31961C4A; // testnet
    // address constant ROOM_MANAGER_PROXY = 0x85f77d7D29e3f641CCdA8AC47c599A97738041B9; // pre-prod
    address constant ROOM_MANAGER_PROXY = 0xbF4E9bF4aefBbA62bA1964fD70f69581bA9691d8; // prod

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        mgr.enableRoomType(IFriendKey.RoomType.Social, IFriendKey.RoomTier.Casual);
        mgr.enableRoomType(IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club);
        mgr.enableRoomType(IFriendKey.RoomType.Social, IFriendKey.RoomTier.Exclusive);
        console2.log("Enabled all tiers for room type Social");

        vm.stopBroadcast();
    }
}

