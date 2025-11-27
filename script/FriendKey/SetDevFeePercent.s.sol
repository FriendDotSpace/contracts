// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetDevFeePercentScript
 * @notice Script to update the dev fee percentage in FriendRoomManager
 */
contract SetDevFeePercentScript is Script {
    // Update this with deployed FriendRoomManager proxy address
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000; // TODO: Update this

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new dev fee percentage (in basis points, e.g., 200 = 2%)
        uint16 newDevFeePercent = uint16(vm.envUint("NEW_DEV_FEE"));

        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager roomManager = FriendRoomManager(ROOM_MANAGER_PROXY);
        (, uint16 creatorFee, uint16 poolFee) = roomManager.getTradingFees();
        roomManager.setTradingFees(newDevFeePercent, creatorFee, poolFee);

        console2.log("Dev fee percent updated to:", newDevFeePercent, "bps");

        vm.stopBroadcast();
    }
}
