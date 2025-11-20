// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract FriendPoolUpgradeScript is Script {
    address constant FRIEND_POOL_PROXY = address(0);

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        if (FRIEND_POOL_PROXY != address(0)) {
            Upgrades.upgradeProxy(FRIEND_POOL_PROXY, "FriendPool.sol", "");
            console2.log("FriendPool upgraded");
        } else {
            console2.log("FriendPool proxy is not set");
        }
        vm.stopBroadcast();
    }
}
