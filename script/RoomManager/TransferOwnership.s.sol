// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title TransferFriendRoomManagerOwnershipScript
 * @notice Script to transfer ownership of FriendRoomManager contract
 */
contract TransferFriendRoomManagerOwnershipScript is Script {
    // Update this with your deployed FriendRoomManager proxy address
    address constant ROOM_MANAGER_PROXY = 0x2212Bdf69A103F67e82A3eB9326C57Ed8619ffaA;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address newOwner = 0xDc32D567Fdffa0D982222b257874f23b5818B7A8;

        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager instance = FriendRoomManager(ROOM_MANAGER_PROXY);
        instance.transferOwnership(newOwner);
        console2.log("FriendRoomManager ownership transferred to:", newOwner);

        vm.stopBroadcast();
    }
}
