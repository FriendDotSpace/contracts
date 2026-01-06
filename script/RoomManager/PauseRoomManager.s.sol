// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title PauseRoomManagerScript
 * @notice Pauses or unpauses the RoomManager
 */
contract PauseRoomManagerScript is Script {
    // Update with deployed RoomManager proxy
    address constant ROOM_MANAGER_PROXY = 0xbF4E9bF4aefBbA62bA1964fD70f69581bA9691d8;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        bool pause = true; // set to false to unpause
        if (pause) {
            mgr.pause();
            console2.log("RoomManager paused");
        } else {
            mgr.unpause();
            console2.log("RoomManager unpaused");
        }

        vm.stopBroadcast();
    }
}

