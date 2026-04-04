// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @notice Validates that all upgradeable contracts are safe implementations.
///         Catches: constructors with state, missing storage gaps, selfdestruct, etc.
///         Relies on @custom:oz-upgrades-unsafe-allow annotations in source contracts.
contract UpgradeSafetyTest is Test {
    function test_FriendKey_validImplementation() public {
        Options memory opts;
        Upgrades.validateImplementation("FriendKey.sol", opts);
    }

    function test_FriendStake_validImplementation() public {
        Options memory opts;
        Upgrades.validateImplementation("FriendStake.sol", opts);
    }

    function test_FriendPool_validImplementation() public {
        Options memory opts;
        Upgrades.validateImplementation("FriendPool.sol", opts);
    }

    function test_FriendRoomManager_validImplementation() public {
        Options memory opts;
        Upgrades.validateImplementation("FriendRoomManager.sol", opts);
    }
}
