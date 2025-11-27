// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
// import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendUSD} from "src/FriendUSD.sol";

contract BuyKeyScript is Script {
    address constant IMPLEMENTATION = 0xB9efc37B877D69FFc7b116b62648C8892C29e53c;
    address constant PROXY = 0x0270f6b4A017750925B8a880b04d64ad0aaE91Ea;
    address constant USDC = 0xC2d95a27116A694565eb14c14A2ae332FFF54e0A;

    uint256 constant TOKEN_ID = 1;
    uint256 constant AMOUNT = 10;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(PROXY);
        FriendUSD usdc = FriendUSD(USDC);

        usdc.approve(PROXY, type(uint256).max);

        instance.buyShares(TOKEN_ID, AMOUNT);

        vm.stopBroadcast();
    }
}
