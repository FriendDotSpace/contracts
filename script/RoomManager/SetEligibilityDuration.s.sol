// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";

/**
 * @title SetEligibilityDurationScript
 * @notice Updates eligibility duration in RoomManager
 */
contract SetEligibilityDurationScript is Script {
    // Update with deployed RoomManager proxy
    address constant ROOM_MANAGER_PROXY = 0x85f77d7D29e3f641CCdA8AC47c599A97738041B9; // pre-prod

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendRoomManager mgr = FriendRoomManager(ROOM_MANAGER_PROXY);

        uint256 newDuration = 1 days;
        mgr.setEligibilityDuration(newDuration);
        console2.log("Eligibility duration set to %s seconds", newDuration);

        vm.stopBroadcast();
    }
}

