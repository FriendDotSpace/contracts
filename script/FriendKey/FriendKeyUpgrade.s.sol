// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";

contract FriendKeyUpgradeScript is Script {
    address constant KEY = 0xdfD77610dd30A21385b1B4C3AA6D20069624F792; // pre-prod
    // address constant KEY = 0x7a1B04a98DF35fa44e998bD62FFC1690A109057D; // testnet

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);

        Upgrades.upgradeProxy(KEY, "FriendKeyV2.sol", "", initialOwner);
        FriendKey instance = FriendKey(KEY);

        console2.log("FriendKey deployed to %s", address(instance));
        vm.stopBroadcast();
    }
}
