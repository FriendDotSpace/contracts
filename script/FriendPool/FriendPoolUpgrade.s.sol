// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract FriendPoolUpgradeScript is Script {
    address constant FRIEND_POOL_PROXY = 0xE0419931d9bCB71F4e529562Cc51a8cd8C3ed1AA;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        if (FRIEND_POOL_PROXY != address(0)) {
        Upgrades.upgradeProxy(FRIEND_POOL_PROXY, "FriendPoolV2.sol", "", initialOwner);
        console2.log("FriendPoolV2 upgraded to V2 at proxy:", FRIEND_POOL_PROXY);
        } else {
            console2.log("FriendPool proxy is not set");
        }
        vm.stopBroadcast();
    }
}
