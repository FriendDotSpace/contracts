// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract FriendStakeUpgradeScript is Script {
    address constant FRIEND_STAKE_PROXY = address(0);

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        if (FRIEND_STAKE_PROXY != address(0)) {
            Upgrades.upgradeProxy(FRIEND_STAKE_PROXY, "FriendStake.sol", "");
        } else {
            console2.log("FriendStake proxy is not set");
        }
        vm.stopBroadcast();
    }
}
