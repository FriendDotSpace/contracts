// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetSocialDivisorsScript
 * @notice Updates social bonding curve divisors in RoomManager
 */
contract SetSocialDivisorsScript is Script {
    // Update with deployed RoomManager proxy
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        // [Casual, Club, Exclusive]
        uint256[3] memory divisors = [uint256(8000), uint256(80), uint256(8)];

        mgr.setSocialDivisors(divisors);
        console2.log("Social divisors set");

        vm.stopBroadcast();
    }
}


