// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendPool} from "src/FriendPool.sol";

/**
 * @title TransferFriendPoolOwnershipScript
 * @notice Script to transfer ownership of FriendPool contract
 */
contract TransferFriendPoolOwnershipScript is Script {
    // Update this with your deployed FriendPool proxy address
    address constant FRIEND_POOL_PROXY = 0xeed00D73776cc6D2D8cdE5a7Bb23186e03706Bd3;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address newOwner = 0xDc32D567Fdffa0D982222b257874f23b5818B7A8;

        vm.startBroadcast(deployerPrivateKey);

        FriendPool instance = FriendPool(FRIEND_POOL_PROXY);
        instance.transferOwnership(newOwner);
        console2.log("FriendPool ownership transferred to:", newOwner);

        vm.stopBroadcast();
    }
}
