// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendKey} from "src/FriendKey.sol";

/**
 * @title SetEligibilityDurationScript
 * @notice Script to update the eligibility duration for FriendKey contract
 */
contract SetEligibilityDurationScript is Script {
    // Update this with your deployed FriendKey proxy address
    address constant FRIEND_KEY_PROXY = 0x295577574FDc19EF2EbC4437462E2F5044591D14;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(FRIEND_KEY_PROXY);

        // Update this with the new eligibility duration (in seconds, e.g., 86400 = 1 day)
        uint256 newEligibilityDuration = vm.envUint("NEW_ELIGIBILITY_DURATION");

        instance.setEligibilityDuration(newEligibilityDuration);
        console2.log("Eligibility duration updated to:", newEligibilityDuration, "seconds");

        vm.stopBroadcast();
    }
}

