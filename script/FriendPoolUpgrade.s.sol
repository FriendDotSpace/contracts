// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendPool} from "src/FriendPool.sol";

contract FriendPoolUpgradeScript is Script {
    address constant POOL = 0x346E34dD169383f0aFfc3a0D0C28Ee3D9B8d8c4E;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);
        

        Upgrades.upgradeProxy(POOL, "FriendPoolV3.sol", "", initialOwner);
        FriendPool instance = FriendPool(POOL);

        console2.log("FriendPool deployed to %s", address(instance));
        vm.stopBroadcast();
    }
}
