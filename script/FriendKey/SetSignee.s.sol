// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendKey} from "src/FriendKey.sol";

/**
 * @title SetSigneeScript
 * @notice Script to update the signee address for FriendKey contract
 */
contract SetSigneeScript is Script {
    // Update this with your deployed FriendKey proxy address
    address constant FRIEND_KEY_PROXY = 0x295577574FDc19EF2EbC4437462E2F5044591D14;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(FRIEND_KEY_PROXY);
        address newSignee = 0x96b4A9c744F813a40b6a4D2B8EC0040E8EC4B788;

        // Update this with the new signee address

        instance.setSignee(newSignee);
        console2.log("Signee updated to:", newSignee);

        vm.stopBroadcast();
    }
}

