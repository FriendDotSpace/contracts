// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetCreatorPerformanceFeePercentScript
 * @notice Script to update the creator performance fee percentage in FriendRoomManager
 */
contract SetCreatorPerformanceFeePercentScript is Script {
    // Update this with deployed FriendRoomManager proxy address
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000; // TODO: Update this

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new creator performance fee percentage (in basis points, e.g., 1500 = 15%)
        uint16 newCreatorPerformanceFeePercent = uint16(vm.envUint("NEW_CREATOR_PERFORMANCE_FEE"));

        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager roomManager = FriendRoomManager(ROOM_MANAGER_PROXY);
        (uint16 devPerformanceFee,) = roomManager.getPerformanceFees();
        roomManager.setPerformanceFees(devPerformanceFee, newCreatorPerformanceFeePercent);

        console2.log("Creator performance fee percent updated to:", newCreatorPerformanceFeePercent, "bps");

        vm.stopBroadcast();
    }
}
