// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {RoomKey} from "src/RoomKey.sol";

contract RoomKeyScript is Script {
    function setUp() public {}

    function run() public {
        // TODO: Set addresses for the variables below, then uncomment the following section:
        /*
    vm.startBroadcast();
    address initialOwner = <Set initialOwner address here>;
    address proxy = Upgrades.deployUUPSProxy(
      "RoomKey.sol",
      abi.encodeCall(RoomKey.initialize, (initialOwner))
    );
    RoomKey instance = RoomKey(proxy);
    console.log("Proxy deployed to %s", address(instance));
    vm.stopBroadcast();
        */
    }
}
