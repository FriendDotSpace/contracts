// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetCreatorFeePercentScript
 * @notice Script to update the creator fee percentage in FriendRoomManager
 */
contract SetCreatorFeePercentScript is Script {
    // Update this with deployed FriendRoomManager proxy address
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000; // TODO: Update this

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new creator fee percentage (in basis points, e.g., 200 = 2%)
        uint16 newCreatorFeePercent = uint16(vm.envUint("NEW_CREATOR_FEE"));

        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager roomManager = FriendRoomManager(ROOM_MANAGER_PROXY);
        (uint16 devFee,, uint16 poolFee) = roomManager.getTradingFees();
        roomManager.setTradingFees(devFee, newCreatorFeePercent, poolFee);

        console2.log("Creator fee percent updated to:", newCreatorFeePercent, "bps");

        vm.stopBroadcast();
    }
}
