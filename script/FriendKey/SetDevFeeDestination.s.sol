// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetDevFeeDestinationScript
 * @notice Script to update the dev fee destination in FriendRoomManager
 */
contract SetDevFeeDestinationScript is Script {
    // Update this with your deployed FriendRoomManager proxy address
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000; // TODO: Update this

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new dev fee destination address
        address newDevFeeDestination = vm.envAddress("NEW_DEV_FEE_DESTINATION");

        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager roomManager = FriendRoomManager(ROOM_MANAGER_PROXY);
        (, address poolDest) = roomManager.getFeeDestinations();
        roomManager.setFeeDestinations(newDevFeeDestination, poolDest);

        console2.log("Dev fee destination updated to:", newDevFeeDestination);

        vm.stopBroadcast();
    }
}
