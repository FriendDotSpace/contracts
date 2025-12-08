// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";
import {IFriendKey} from "src/interfaces/IFriendKey.sol";

/**
 * @title EnableRoomTypeScript
 * @notice Enables a room type/tier with default limit (1) in RoomManager
 */
contract EnableRoomTypeScript is Script {
    // Update with deployed RoomManager proxy
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        IFriendKey.RoomType roomType = IFriendKey.RoomType.Social;
        IFriendKey.RoomTier tier = IFriendKey.RoomTier.Club;

        mgr.enableRoomType(roomType, tier);
        console2.log("Enabled room type %s tier %s", uint256(roomType), uint256(tier));

        vm.stopBroadcast();
    }
}


