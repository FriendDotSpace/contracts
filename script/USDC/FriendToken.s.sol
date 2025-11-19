// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendUSD} from "src/FriendUSD.sol";

contract FriendTokenScript is Script {
    address constant PROXY = 0x99415d18C146Daf43Fe4D6685224D820Ff03F16d;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);

        FriendUSD instance = new FriendUSD(initialOwner);
        console2.log("Instance deployed to %s", address(instance));
        vm.stopBroadcast();
    }

    function mint() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address to = 0x4Ad0a42b28E945C8774F382D747F992feA268db6;
        vm.startBroadcast(deployerPrivateKey);

        FriendUSD instance = FriendUSD(PROXY);
        instance.mint(to, 1000 * 10 ** 6);
        vm.stopBroadcast();
    }
}
