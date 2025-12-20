// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendPool} from "src/FriendPool.sol";

/**
 * @title SetDispatcherScript
 * @notice Script to update the dispatcher address for FriendPool contract
 */
contract SetDispatchFeeScript is Script {
    address constant FRIEND_POOL_PROXY = 0xE0419931d9bCB71F4e529562Cc51a8cd8C3ed1AA;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new dispatcher address
        uint256 newDispatchFee = 3 * 10 ** 6;

        vm.startBroadcast(deployerPrivateKey);

        FriendPool instance = FriendPool(FRIEND_POOL_PROXY);

        instance.setDispatchFee(newDispatchFee);
        console2.log("Dispatch fee updated to:", newDispatchFee);
        vm.stopBroadcast();
    }
}

