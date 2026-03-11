// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TransferFriendStakeBeaconOwnershipScript
 * @notice Script to transfer ownership of FriendStake Beacon (UpgradeableBeacon)
 * @dev The beacon controls upgrades for all FriendStake BeaconProxy instances
 */
contract TransferFriendStakeBeaconOwnershipScript is Script {
    // Update this with your deployed FriendStake beacon address
    address constant FRIEND_STAKE_BEACON = 0xDD46b303246fF3E5564783cE0Ad4Ea230dF728ed;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address newOwner = 0xDc32D567Fdffa0D982222b257874f23b5818B7A8;

        vm.startBroadcast(deployerPrivateKey);

        Ownable beacon = Ownable(FRIEND_STAKE_BEACON);
        beacon.transferOwnership(newOwner);
        console2.log("FriendStake Beacon ownership transferred to:", newOwner);

        vm.stopBroadcast();
    }
}
