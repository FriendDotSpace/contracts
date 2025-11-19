// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendPool} from "src/FriendPool.sol";

contract FriendPoolScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);

        // Base mainnet addresses
        address friendKey = 0x023CB1160fCEFadced0A4C21fb99ea628E807717;
        address dlnSource = 0xFF7D9a483d0820cc5286E37ed5184e7dBc52B6F4;

        bytes memory initializeData = abi.encodeCall(FriendPool.initialize, (initialOwner, friendKey, dlnSource));
        address proxy = Upgrades.deployUUPSProxy("FriendPool.sol", initializeData);
        FriendPool instance = FriendPool(proxy);
        console2.log("FriendPool deployed to %s", address(instance));
        vm.stopBroadcast();
    }
}
