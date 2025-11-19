// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendStake} from "src/FriendStake.sol";

/**
 * @title SetAuthorityScript
 * @notice Script to update the authority address for a FriendStake contract
 * @dev Note: FriendStake contracts are deployed per token ID via beacon proxy
 *      Update the STAKING_POOL_ADDRESS constant with the specific staking pool address
 */
contract SetAuthorityScript is Script {
    // Update this with the specific FriendStake contract address (beacon proxy instance)
    // You can find this via: FriendKey.stakingPoolByTokenId(tokenId)
    address constant STAKING_POOL_ADDRESS = address(0); // Update with actual staking pool address

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Update this with the new authority address
        address newAuthority = 0x0000000000000000000000000000000000000000;

        vm.startBroadcast(deployerPrivateKey);

        FriendStake instance = FriendStake(STAKING_POOL_ADDRESS);
        if (newAuthority != address(0)) {
            instance.setAuthority(newAuthority);
            console2.log("Authority updated to:", newAuthority);
        }

        vm.stopBroadcast();
    }
}

