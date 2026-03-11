// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";

contract FriendKeyUpgradeScript is Script {
    // address constant KEY = 0x4eF7037118303098bd7EbA64feB19d9d7D7e3682; // pre-prod
    address constant KEY = 0x76357013CE72c13c736A897a4F905f59A08e3154; // testnet

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
