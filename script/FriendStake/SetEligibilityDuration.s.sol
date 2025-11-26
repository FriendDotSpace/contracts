// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendStake} from "src/FriendStake.sol";

/**
 * @title SetEligibilityDurationScript
 * @notice Script to update the eligibility duration for a FriendStake contract
 * @dev Note: FriendStake contracts are deployed per token ID via beacon proxy
 *      Update the STAKING_POOL_ADDRESS constant with the specific staking pool address
 */
contract SetEligibilityDurationScript is Script {
    // Update this with the specific FriendStake contract address (beacon proxy instance)
    // You can find this via: FriendKey.stakingPoolByTokenId(tokenId)
    address constant STAKING_POOL_ADDRESS = address(0); // Update with actual staking pool address

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new eligibility duration (in seconds, e.g., 86400 = 1 day)
        uint256 newEligibilityDuration = 86400;
        vm.startBroadcast(deployerPrivateKey);

        FriendStake instance = FriendStake(STAKING_POOL_ADDRESS);
        if (STAKING_POOL_ADDRESS != address(0)) {
            instance.setEligibilityDuration(newEligibilityDuration);
            console2.log("Eligibility duration updated to:", newEligibilityDuration, "seconds");
        }
        vm.stopBroadcast();
    }
}

