// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {FriendRoomManager} from "../src/FriendRoomManager.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployRoomManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address friendKeyAddress = vm.envAddress("FRIEND_KEY_ADDRESS");
        address owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy RoomManager
        bytes memory roomManagerInitData = abi.encodeCall(FriendRoomManager.initialize, (owner));

        address roomManagerProxy = Upgrades.deployUUPSProxy("FriendRoomManager.sol", roomManagerInitData);

        FriendRoomManager roomManager = FriendRoomManager(roomManagerProxy);
        roomManager.setFriendKey(friendKeyAddress);

        // Optional: Set custom limits
        // roomManager.setMaxRoomsPerTier(RoomType.Social, RoomTier.Casual, 10);

        vm.stopBroadcast();

        console.log("FriendRoomManager deployed at:", address(roomManager));
        console.log("Remember to call FriendKey.setRoomManager() with this address to enable limits");
    }
}
