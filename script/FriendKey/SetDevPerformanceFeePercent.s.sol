// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendKey} from "src/FriendKey.sol";

/**
 * @title SetDevPerformanceFeePercentScript
 * @notice Script to update the development performance fee percentage for FriendKey contract
 */
contract SetDevPerformanceFeePercentScript is Script {
    // Update this with your deployed FriendKey proxy address
    address constant FRIEND_KEY_PROXY = 0x295577574FDc19EF2EbC4437462E2F5044591D14;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(FRIEND_KEY_PROXY);

        // Update this with the new dev performance fee percentage (in basis points, e.g., 500 = 5%)
        uint256 newDevPerformanceFeePercent = vm.envUint("NEW_DEV_PERFORMANCE_FEE_PERCENT");

        instance.setDevPerformanceFeePercent(newDevPerformanceFeePercent);
        console2.log("Dev performance fee percent updated to:", newDevPerformanceFeePercent, "bps");

        vm.stopBroadcast();
    }
}

