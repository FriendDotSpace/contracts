// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendKey} from "src/FriendKey.sol";

/**
 * @title SetTradingPoolFeeDestinationScript
 * @notice Script to update the trading pool fee destination address for FriendKey contract
 */
contract SetTradingPoolFeeDestinationScript is Script {
    // Update this with your deployed FriendKey proxy address
    address constant FRIEND_KEY_PROXY = 0x295577574FDc19EF2EbC4437462E2F5044591D14;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new trading pool fee destination address
        address newTradingPoolFeeDestination = 0x0000000000000000000000000000000000000000;
        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(FRIEND_KEY_PROXY);
        if (newTradingPoolFeeDestination != address(0)) {
            instance.setTradingPoolFeeDestination(newTradingPoolFeeDestination);
            console2.log("Trading pool fee destination updated to:", newTradingPoolFeeDestination);
        }
        vm.stopBroadcast();
    }
}

