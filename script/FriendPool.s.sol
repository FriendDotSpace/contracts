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

        // Base sepolia addresses
        address friendKey = 0x4eF7037118303098bd7EbA64feB19d9d7D7e3682;
        address dlnSource = 0xFF7D9a483d0820cc5286E37ed5184e7dBc52B6F4;
        // Base mainnet addresses
        // address friendKey = 0x1F773125477E1DbC1b2C9ce43eAd596c648e4324;
        // address dlnSource = 0xeF4fB24aD0916217251F553c0596F8Edc630EB66;

        bytes memory initializeData = abi.encodeCall(FriendPool.initialize, (initialOwner, friendKey, dlnSource));
        address proxy = Upgrades.deployUUPSProxy("FriendPool.sol", initializeData);
        FriendPool instance = FriendPool(proxy);
        console2.log("FriendPool deployed to %s", address(instance));
        vm.stopBroadcast();
    }
}
