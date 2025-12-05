// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetTradingPoolFeeDestinationScript
 * @notice Script to update the trading pool fee destination in FriendRoomManager
 */
contract SetTradingPoolFeeDestinationScript is Script {
    // Update this with deployed FriendRoomManager proxy address
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000; // TODO: Update this

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new trading pool fee destination address
        address newPoolFeeDestination = vm.envAddress("NEW_POOL_FEE_DESTINATION");

        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager roomManager = FriendRoomManager(ROOM_MANAGER_PROXY);
        (address devDest,) = roomManager.getFeeDestinations();
        roomManager.setFeeDestinations(devDest, newPoolFeeDestination);

        console2.log("Trading pool fee destination updated to:", newPoolFeeDestination);

        vm.stopBroadcast();
    }
}
