// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
// import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendUSD} from "src/FriendUSD.sol";

contract FaucetScript is Script {
    address constant USDC = 0xC2d95a27116A694565eb14c14A2ae332FFF54e0A;

    uint256 constant TIMES = 32;
    uint256 constant AMOUNT = 100e6;
    uint256 constant ADDRESS_COUNT = 4;

    address[ADDRESS_COUNT] RECIPIENTS = [
        0x9434A99Ac858Dc645EBDc9AA551730A89c9dD0B3,
        0xe18b241E97793C05d7dF05d0C1a3Dec8ac08586D,
        0x77B17522774DB8F531dDA6ddB953518987F3171A,
        0x2dae800607f03331b2796BA17C7250C2F1F49Bc8
    ];

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendUSD usdc = FriendUSD(USDC);

        for (uint256 i = 0; i < RECIPIENTS.length * TIMES; i++) {
            uint256 index = i % RECIPIENTS.length;
            console2.log("Minting to:", RECIPIENTS[index], "Amount:", AMOUNT);
            usdc.mint(RECIPIENTS[index], AMOUNT);
        }

        vm.stopBroadcast();
    }
}
