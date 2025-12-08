// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetTradingFeesScript
 * @notice Updates trading fees (dev / creator / pool) in RoomManager
 */
contract SetTradingFeesScript is Script {
    // Update with deployed RoomManager proxy
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        // Basis points (1% = 100)
        uint16 devFee = 200; // 2%
        uint16 creatorFee = 200; // 2%
        uint16 poolFee = 600; // 6%

        mgr.setTradingFees(devFee, creatorFee, poolFee);
        console2.log("Trading fees set: dev %s, creator %s, pool %s", devFee, creatorFee, poolFee);

        vm.stopBroadcast();
    }
}

