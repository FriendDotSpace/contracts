// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendKey} from "src/FriendKey.sol";

/**
 * @title SetCreatorFeePercentScript
 * @notice Script to update the creator fee percentage for FriendKey contract
 */
contract SetCreatorFeePercentScript is Script {
    // Update this with your deployed FriendKey proxy address
    address constant FRIEND_KEY_PROXY = 0x295577574FDc19EF2EbC4437462E2F5044591D14;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new creator fee percentage (in basis points, e.g., 200 = 2%)
        uint256 newCreatorFeePercent = 200;
        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(FRIEND_KEY_PROXY);
        instance.setTradingFees(
            instance.devFeePercent(), uint16(newCreatorFeePercent), instance.tradingPoolFeePercent()
        );
        console2.log("Creator fee percent updated to:", newCreatorFeePercent, "bps");

        vm.stopBroadcast();
    }
}

