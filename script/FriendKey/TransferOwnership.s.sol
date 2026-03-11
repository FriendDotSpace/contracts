// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendKey} from "src/FriendKey.sol";

/**
 * @title TransferFriendKeyOwnershipScript
 * @notice Script to transfer ownership of FriendKey contract
 */
contract TransferFriendKeyOwnershipScript is Script {
    // Update this with your deployed FriendKey proxy address
    address constant FRIEND_KEY_PROXY = 0x76357013CE72c13c736A897a4F905f59A08e3154;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address newOwner = 0xDc32D567Fdffa0D982222b257874f23b5818B7A8;

        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(FRIEND_KEY_PROXY);
        instance.transferOwnership(newOwner);
        console2.log("FriendKey ownership transferred to:", newOwner);

        vm.stopBroadcast();
    }
}
