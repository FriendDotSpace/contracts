// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract FriendStakeUpgradeScript is Script {
    // address constant FRIEND_STAKE_BEACON = 0x9e853ab756422D7612548E940f495c456E11DF39; // testnet
    // address constant FRIEND_STAKE_BEACON = 0x53BdEfB3E2faEB90b766B459AF96F3E357D3c3f9; // prod
    address constant FRIEND_STAKE_BEACON = 0x2e03f3b2C0845b3b9e7B63E55280D93C1577D634; // pre-prod beacon
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        if (FRIEND_STAKE_BEACON != address(0)) {
            Upgrades.upgradeBeacon(FRIEND_STAKE_BEACON, "FriendStakeV3.sol");
        } else {
            console2.log("FriendStake beacon is not set");
        }
        vm.stopBroadcast();
    }
}
