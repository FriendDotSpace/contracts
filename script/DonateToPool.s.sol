// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendPoolV3} from "src/upgrades/FriendPoolV3.sol";

contract DonateToPoolScript is Script {
    address constant POOL = 0x346E34dD169383f0aFfc3a0D0C28Ee3D9B8d8c4E;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        FriendPoolV3 instance = FriendPoolV3(POOL);
        uint256 tokenId = 1; // Example tokenId
        // assert that the trading pool fee destination is set correctly
        instance.donate(tokenId, 1e6);

        vm.stopBroadcast();
    }
}
