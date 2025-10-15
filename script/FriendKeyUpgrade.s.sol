// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKeyV2} from "src/upgrades/FriendKeyV2.sol";
import {FriendStake} from "src/FriendStakeV2.sol";

contract FriendKeyUpgradeScript is Script {
    address constant KEY = 0x1F773125477E1DbC1b2C9ce43eAd596c648e4324;
    address constant AUTHORITY = 0xe18b241E97793C05d7dF05d0C1a3Dec8ac08586D;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);

        Upgrades.upgradeProxy(KEY, "FriendKeyV2.sol", "", initialOwner);
        FriendKeyV2 instance = FriendKeyV2(KEY);

        console2.log("FriendKey upgraded at proxy %s", address(instance));
        instance.setAuthority(AUTHORITY);

        FriendStake friendStake = new FriendStake();
        instance.setFriendStake(address(friendStake));
        console2.log("New FriendStake implementation deployed at %s", address(friendStake));

        vm.stopBroadcast();
    }
}
