// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
// import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";

contract RegisterKeyScript is Script {

    address constant IMPLEMENTATION = 0xB9efc37B877D69FFc7b116b62648C8892C29e53c;
    address constant PROXY = 0x0270f6b4A017750925B8a880b04d64ad0aaE91Ea;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(PROXY);

        console2.log("Proxy deployed to %s", address(instance));

        instance.registerCreator();
        
        vm.stopBroadcast();
    }
}
