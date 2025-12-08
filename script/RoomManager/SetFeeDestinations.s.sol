// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetFeeDestinationsScript
 * @notice Updates dev fee and pool fee destinations in RoomManager
 */
contract SetFeeDestinationsScript is Script {
    // Update with deployed RoomManager proxy
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        // Configure destinations
        address devDest = 0x000000000000000000000000000000000000dEaD;
        address poolDest = 0x000000000000000000000000000000000000bEEF;

        mgr.setFeeDestinations(devDest, poolDest);
        console2.log("Fee destinations set: dev %s, pool %s", devDest, poolDest);

        vm.stopBroadcast();
    }
}


