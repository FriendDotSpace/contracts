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
    address constant ROOM_MANAGER_PROXY = 0xbF4E9bF4aefBbA62bA1964fD70f69581bA9691d8; // prod

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        // Configure destinations
        address devDest = 0x953832A125B091cC8C99f90d2f7DaB79e8326076; // prod
        address poolDest = 0xa1bf9bb17C283CF17F01516f78f3127D2C84C79d; // prod

        mgr.setFeeDestinations(devDest, poolDest);
        console2.log("Fee destinations set: dev %s, pool %s", devDest, poolDest);

        vm.stopBroadcast();
    }
}

