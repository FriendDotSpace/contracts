// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetAuthorityScript
 * @notice Script to update the authority address in FriendRoomManager
 */
contract SetAuthorityScript is Script {
    // Update this with deployed FriendRoomManager proxy address
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000; // TODO: Update this

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new authority address
        address newAuthority = vm.envAddress("NEW_AUTHORITY");

        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager roomManager = FriendRoomManager(ROOM_MANAGER_PROXY);
        roomManager.setAuthority(newAuthority);

        console2.log("Authority updated to:", newAuthority);

        vm.stopBroadcast();
    }
}

