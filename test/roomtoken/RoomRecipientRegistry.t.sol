// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RoomRecipientRegistry} from "../../src/roomtoken/RoomRecipientRegistry.sol";

contract RoomRecipientRegistryTest is Test {
    RoomRecipientRegistry internal registry;
    address internal safe = makeAddr("platformSafe");
    address internal defaultPlatform = makeAddr("defaultPlatform");

    function setUp() public {
        registry = new RoomRecipientRegistry(safe, defaultPlatform);
    }

    function test_unsetRoomFallsBackToDefaultPlatformAndZeroRoomFund() public view {
        (address roomFund, address platform) = registry.recipientsOf(42);
        assertEq(roomFund, address(0));
        assertEq(platform, defaultPlatform);
    }

    function test_ownerSetsRecipientsAndResolutionFollows() public {
        address fund = makeAddr("roomWallet42");
        address plat = makeAddr("platform42");
        vm.prank(safe);
        registry.setRecipients(42, fund, plat);
        (address roomFund, address platform) = registry.recipientsOf(42);
        assertEq(roomFund, fund);
        assertEq(platform, plat);
    }

    function test_nonOwnerCannotSetRecipients() public {
        vm.expectRevert();
        registry.setRecipients(42, address(1), address(2));
    }

    function test_ownerRotatesDefaultPlatform() public {
        address next = makeAddr("nextPlatform");
        vm.prank(safe);
        registry.setDefaultPlatformRecipient(next);
        (, address platform) = registry.recipientsOf(7);
        assertEq(platform, next);
    }

    function test_ownershipTransferRequiresAcceptance() public {
        address nextSafe = makeAddr("nextSafe");
        vm.prank(safe);
        registry.transferOwnership(nextSafe);
        // Two-step: owner() must NOT change until the pending owner accepts.
        assertEq(registry.owner(), safe);
        assertEq(registry.pendingOwner(), nextSafe);

        vm.prank(nextSafe);
        registry.acceptOwnership();
        assertEq(registry.owner(), nextSafe);
        assertEq(registry.pendingOwner(), address(0));
    }
}
