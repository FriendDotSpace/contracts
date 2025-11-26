// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendPool} from "src/FriendPool.sol";

/**
 * @title SetDispatcherScript
 * @notice Script to update the dispatcher address for FriendPool contract
 */
contract SetDispatcherScript is Script {
    // Update this with your deployed FriendPool proxy address
    address constant FRIEND_POOL_PROXY = 0x2CAe4753B44bc41210b2126bACa5f4910fD7974C;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new dispatcher address
        address newDispatcher = 0x0000000000000000000000000000000000000000;

        vm.startBroadcast(deployerPrivateKey);

        FriendPool instance = FriendPool(FRIEND_POOL_PROXY);

        if (newDispatcher != address(0)) {
            instance.setDispatcher(newDispatcher);
            console2.log("Dispatcher updated to:", newDispatcher);
        }
        vm.stopBroadcast();
    }
}

