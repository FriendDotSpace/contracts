// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendUSD} from "src/FriendUSD.sol";

contract FriendTokenScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);

        FriendUSD instance = new FriendUSD(initialOwner);
        console2.log("Instance deployed to %s", address(instance));
        vm.stopBroadcast();
    }
}
