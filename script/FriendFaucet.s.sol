// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendFaucet} from "src/FriendFaucet.sol";

contract FriendFaucetScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address usdc = 0xC2d95a27116A694565eb14c14A2ae332FFF54e0A;

        address initialOwner = vm.addr(deployerPrivateKey);

        FriendFaucet instance = new FriendFaucet(initialOwner, usdc);
        console2.log("Instance deployed to %s", address(instance));
        vm.stopBroadcast();
    }
}
