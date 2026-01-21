// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendRoomManagerV2} from "src/FriendRoomManagerV2.sol";
import {IFriendKey} from "src/interfaces/IFriendKey.sol";

contract FriendRoomManagerUpgradeScript is Script {
    // Update this address based on your deployment
    address constant ROOM_MANAGER_PROXY = 0x4a31C071e797d8B818B67a80768e35EE31961C4A; // testnet
    // address constant ROOM_MANAGER_PROXY = 0x85f77d7D29e3f641CCdA8AC47c599A97738041B9; // pre-prod
    // address constant ROOM_MANAGER_PROXY = 0x94C36A05D72C75d70eDa968FFa034a018508018A; // prod

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Upgrading FriendRoomManager to V2 ===");
        console2.log("Proxy address:", ROOM_MANAGER_PROXY);
        console2.log("Owner:", initialOwner);

        // Upgrade the proxy to V2
        Upgrades.upgradeProxy(ROOM_MANAGER_PROXY, "FriendRoomManagerV2.sol", "");
        console2.log("FriendRoomManager upgraded to V2");

        // Cast to V2 to access new functions
        FriendRoomManagerV2 roomManager = FriendRoomManagerV2(ROOM_MANAGER_PROXY);

        // Set max rooms per type for Social rooms to 1 (any tier)
        roomManager.setMaxRoomsPerType(IFriendKey.RoomType.Social, 1);
        console2.log("Set maxRoomsPerType for Social rooms to 1");

        // Verify the setting
        uint256 maxSocialRooms = roomManager.maxRoomsPerType(IFriendKey.RoomType.Social);
        console2.log("Verified maxRoomsPerType[Social]:", maxSocialRooms);

        console2.log("=== Upgrade Complete ===");
        console2.log("Social rooms are now limited to 1 total per creator (any tier)");

        vm.stopBroadcast();
    }
}
