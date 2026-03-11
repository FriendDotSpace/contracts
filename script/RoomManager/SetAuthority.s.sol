// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetAuthorityScript (RoomManager)
 * @notice Updates authority address in RoomManager
 */
contract SetAuthorityScript is Script {
    // Update with deployed RoomManager proxy
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        address newAuthority = 0x0000000000000000000000000000000000001234;
        mgr.setAuthority(newAuthority);
        console2.log("Authority set to %s", newAuthority);

        vm.stopBroadcast();
    }
}

//   Bonding Token: 0x5a08caD340845F050af95E510AfCEE03d3E3de4D
//   FriendStake Beacon: 0xDD46b303246fF3E5564783cE0Ad4Ea230dF728ed
//   FriendKey Proxy: 0x76357013CE72c13c736A897a4F905f59A08e3154
//   FriendPool Proxy: 0xeed00D73776cc6D2D8cdE5a7Bb23186e03706Bd3
//   DLN Source: 0xDc32D567Fdffa0D982222b257874f23b5818B7A8
//   Authority: 0x0fc7d5925B7519062f10c0b659dC9f1371B42B52
//   Signee: 0x0fc7d5925B7519062f10c0b659dC9f1371B42B52
//   FriendRoomManager Proxy: 0x2212Bdf69A103F67e82A3eB9326C57Ed8619ffaA