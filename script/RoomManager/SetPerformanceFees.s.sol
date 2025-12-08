// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetPerformanceFeesScript
 * @notice Updates performance fees (dev / creator) in RoomManager
 */
contract SetPerformanceFeesScript is Script {
    // Update with deployed RoomManager proxy
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        // Basis points (1% = 100)
        uint16 devPerf = 500; // 5%
        uint16 creatorPerf = 1500; // 15%

        mgr.setPerformanceFees(devPerf, creatorPerf);
        console2.log("Performance fees set: dev %s, creator %s", devPerf, creatorPerf);

        vm.stopBroadcast();
    }
}

