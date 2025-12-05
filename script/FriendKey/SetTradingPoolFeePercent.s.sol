// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetTradingPoolFeePercentScript
 * @notice Script to update the trading pool fee percentage in FriendRoomManager
 */
contract SetTradingPoolFeePercentScript is Script {
    // Update this with deployed FriendRoomManager proxy address
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000; // TODO: Update this

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new trading pool fee percentage (in basis points, e.g., 600 = 6%)
        uint16 newTradingPoolFeePercent = uint16(vm.envUint("NEW_POOL_FEE"));

        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager roomManager = FriendRoomManager(ROOM_MANAGER_PROXY);
        (uint16 devFee, uint16 creatorFee,) = roomManager.getTradingFees();
        roomManager.setTradingFees(devFee, creatorFee, newTradingPoolFeePercent);

        console2.log("Trading pool fee percent updated to:", newTradingPoolFeePercent, "bps");

        vm.stopBroadcast();
    }
}
