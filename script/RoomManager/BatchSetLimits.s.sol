// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";
import {IFriendKey} from "src/interfaces/IFriendKey.sol";

/**
 * @title BatchSetLimitsScript
 * @notice Batch updates max room limits for multiple room type/tier pairs
 */
contract BatchSetLimitsScript is Script {
    // Update with deployed RoomManager proxy
    address constant ROOM_MANAGER_PROXY = 0x0000000000000000000000000000000000000000;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        // Configure arrays before running
        IFriendKey.RoomType[] memory roomTypes = new IFriendKey.RoomType[](3);
        IFriendKey.RoomTier[] memory tiers = new IFriendKey.RoomTier[](3);
        uint256[] memory limits = new uint256[](3);

        roomTypes[0] = IFriendKey.RoomType.Trading;
        tiers[0] = IFriendKey.RoomTier.Club;
        limits[0] = 3;

        roomTypes[1] = IFriendKey.RoomType.Trading;
        tiers[1] = IFriendKey.RoomTier.Exclusive;
        limits[1] = 2;

        roomTypes[2] = IFriendKey.RoomType.Social;
        tiers[2] = IFriendKey.RoomTier.Club;
        limits[2] = 5;

        mgr.batchSetLimits(roomTypes, tiers, limits);
        console2.log("Batch set limits executed");

        vm.stopBroadcast();
    }
}

