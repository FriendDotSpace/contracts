// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";
import {IFriendKey} from "src/interfaces/IFriendKey.sol";

/**
 * @title SetMaxRoomsPerTierScript
 * @notice Updates the max room limit for a given room type and tier
 */
contract SetMaxRoomsPerTierScript is Script {
    // Update with deployed RoomManager proxy
    address constant ROOM_MANAGER_PROXY = 0x4a31C071e797d8B818B67a80768e35EE31961C4A;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        // Configure these before running
        IFriendKey.RoomType roomType = IFriendKey.RoomType.Trading; // Trading or Social
        IFriendKey.RoomTier tier = IFriendKey.RoomTier.Exclusive; // Casual / Club / Exclusive
        uint256 newLimit = 10;

        mgr.setMaxRoomsPerTier(roomType, tier, newLimit);
        console2.log("Set max rooms", uint256(roomType), uint256(tier), newLimit);

        vm.stopBroadcast();
    }
}

