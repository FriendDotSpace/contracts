// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
// import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";

contract RegisterKeyScript is Script {
    address constant IMPLEMENTATION = 0x3a6D7Fb39fa60d5d758b3A7b3b8AC97ad58A4912;
    address constant PROXY = 0xd950960D03777D9355421a1F0b5ff165BDAf29A6;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(PROXY);

        console2.log("Proxy deployed to %s", address(instance));

        instance.registerCreator();

        vm.stopBroadcast();
    }
}
