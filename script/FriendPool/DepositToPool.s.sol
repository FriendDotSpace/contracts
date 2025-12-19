// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FriendPool} from "src/FriendPoolV2.sol";

/**
 * @title DepositToPoolScript
 * @notice Deposits bonding tokens into FriendPoolV2 reserves for a specific tokenId
 */
contract DepositToPoolScript is Script {
    // Set these before running
    address constant FRIEND_POOL_PROXY = 0xE0419931d9bCB71F4e529562Cc51a8cd8C3ed1AA;
    uint256 constant TOKEN_ID = 3; // room tokenId to credit
    uint256 constant AMOUNT = 10_000_000; // example: 5 USDC with 6 decimals

    function setUp() public {}

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        FriendPool pool = FriendPool(FRIEND_POOL_PROXY);
        IERC20Metadata bondingToken = IERC20Metadata(pool.friendKey().bondingToken());

        // Ensure allowance
        bondingToken.approve(FRIEND_POOL_PROXY, AMOUNT);

        // Deposit
        pool.depositToPool(TOKEN_ID, AMOUNT);
        console2.log("Deposited %s to tokenId %s into FriendPoolV2", AMOUNT, TOKEN_ID);

        vm.stopBroadcast();
    }
}

