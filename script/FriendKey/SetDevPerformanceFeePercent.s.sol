// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetDevPerformanceFeePercentScript
 * @notice Script to update the dev performance fee percentage in FriendRoomManager
 */
contract SetDevPerformanceFeePercentScript is Script {
    // Update this with deployed FriendRoomManager proxy address
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000; // TODO: Update this

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new dev performance fee percentage (in basis points, e.g., 500 = 5%)
        uint16 newDevPerformanceFeePercent = uint16(vm.envUint("NEW_DEV_PERFORMANCE_FEE"));

        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager roomManager = FriendRoomManager(ROOM_MANAGER_PROXY);
        (, uint16 creatorPerformanceFee) = roomManager.getPerformanceFees();
        roomManager.setPerformanceFees(newDevPerformanceFeePercent, creatorPerformanceFee);

        console2.log("Dev performance fee percent updated to:", newDevPerformanceFeePercent, "bps");

        vm.stopBroadcast();
    }
}
