// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendStake} from "src/FriendStake.sol";

/// @notice Batch updates bridgeFee on all existing staking pools by scanning tokenIds.
/// @dev Provide FRIEND_KEY and MAX_TOKEN_ID via env; pools with address(0) are skipped.
contract BatchSetBridgeFee is Script {
    address public FRIEND_KEY = 0xAF0Bf8593dC6CA973DF2132731B0F9B5F974FA9F; // preprod
    // Inclusive upper bound to scan tokenIds [1..MAX_TOKEN_ID]
    uint256 public MAX_TOKEN_ID = vm.envOr("MAX_TOKEN_ID", uint256(1534));
    // New bridge fee; defaults to 3 USDC (6 decimals)
    // uint256 public BRIDGE_FEE = vm.envOr("BRIDGE_FEE", uint256(3 * 10 ** 6));
    uint256 public BRIDGE_FEE = 100000;

    function run() external {
        require(FRIEND_KEY != address(0), "FRIEND_KEY not set");
        require(MAX_TOKEN_ID > 0, "MAX_TOKEN_ID not set");

        uint256 pk = vm.envUint("PRIVATE_KEY"); // owner of staking pools
        vm.startBroadcast(pk);

        FriendKey fk = FriendKey(FRIEND_KEY);
        uint256 updated;

        for (uint256 id = 1534; id <= MAX_TOKEN_ID; id++) {
            address stakeAddr = fk.stakingPoolByTokenId(id);
            if (stakeAddr == address(0)) {
                continue;
            }
            // Only touch trading rooms with a staking pool
            try FriendStake(stakeAddr).setBridgeFee(BRIDGE_FEE) {
                updated++;
                console2.log("Updated bridgeFee for tokenId", id, "stake", stakeAddr);
            } catch {
                console2.log("Skip tokenId (call failed)", id, stakeAddr);
            }
        }

        console2.log("Completed. Updated pools:", updated);
        vm.stopBroadcast();
    }
}
