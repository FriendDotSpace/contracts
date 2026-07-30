// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Harness} from "./Harness.t.sol";
import {RoomFeeSplitter, Leg} from "../../src/roomtoken/RoomFeeSplitter.sol";
import {IUniswapV3PoolMinimal} from "../../src/roomtoken/interfaces/IUniswapV3PoolMinimal.sol";

contract RoomFeeSplitterTest is Harness {
    function setUp() public {
        setUpHarness();
    }

    function test_poolInitializedAtInitTick() public view {
        (, int24 tick,,,,,) = pool.slot0();
        assertEq(tick, INIT_TICK);
    }

    function test_collectQuoteSplitsSixtyTwentyFiveFifteen() public {
        openTrading();
        buy(makeAddr("whale"), 1_000_000_000); // $1,000 → ~$10 of quote-side fees
        uint256 collected = splitter.collectQuote();
        assertGt(collected, 0);
        uint256 c = splitter.ledgerOf(Leg.Creator);
        uint256 f = splitter.ledgerOf(Leg.RoomFund);
        uint256 p = splitter.ledgerOf(Leg.Platform);
        assertEq(c, (collected * 6000) / 10_000);
        assertEq(f, (collected * 2500) / 10_000);
        assertEq(p, collected - c - f); // platform absorbs rounding dust
    }

    function test_collectQuoteIsPermissionless() public {
        openTrading();
        buy(makeAddr("whale"), 1_000_000_000);
        vm.prank(makeAddr("randomKeeper"));
        splitter.collectQuote();
    }

    function test_claimPaysResolvedRecipientsAndZeroesLedger() public {
        openTrading();
        buy(makeAddr("whale"), 1_000_000_000);
        splitter.collectQuote();
        uint256 creatorDue = splitter.ledgerOf(Leg.Creator);
        uint256 fundDue = splitter.ledgerOf(Leg.RoomFund);

        splitter.claim(Leg.Creator);
        splitter.claim(Leg.RoomFund);
        splitter.claim(Leg.Platform);

        assertEq(usdg.balanceOf(creator), creatorDue);
        assertEq(usdg.balanceOf(roomWallet), fundDue);
        assertGt(usdg.balanceOf(defaultPlatform), 0);
        assertEq(splitter.ledgerOf(Leg.Creator), 0);
        vm.expectRevert(RoomFeeSplitter.NothingToClaim.selector);
        splitter.claim(Leg.Creator);
    }

    function test_creatorRedirectAppliesToUnclaimedBalance() public {
        openTrading();
        buy(makeAddr("whale"), 1_000_000_000);
        splitter.collectQuote();
        address newWallet = makeAddr("creatorNewWallet");
        vm.prank(creator);
        splitter.setCreatorRecipient(newWallet);
        uint256 due = splitter.ledgerOf(Leg.Creator);
        splitter.claim(Leg.Creator);
        assertEq(usdg.balanceOf(newWallet), due);
        assertEq(usdg.balanceOf(creator), 0);
    }

    function test_platformProposalHonorsTimelockAndExpiry() public {
        address rescue = makeAddr("rescueWallet");
        vm.prank(platformSafe);
        splitter.proposeCreatorRecipient(rescue);

        vm.expectRevert(RoomFeeSplitter.ProposalNotReady.selector);
        splitter.executeProposedCreatorRecipient();

        vm.warp(block.timestamp + 3 days);
        splitter.executeProposedCreatorRecipient();
        assertEq(splitter.creatorRecipient(), rescue);
    }

    function test_platformProposalExpires() public {
        vm.prank(platformSafe);
        splitter.proposeCreatorRecipient(makeAddr("rescue"));
        vm.warp(block.timestamp + 3 days + 7 days);
        vm.expectRevert(RoomFeeSplitter.ProposalExpired.selector);
        splitter.executeProposedCreatorRecipient();
    }

    function test_creatorRedirectCancelsPendingProposal() public {
        vm.prank(platformSafe);
        splitter.proposeCreatorRecipient(makeAddr("attackerRescue"));
        vm.prank(creator);
        splitter.setCreatorRecipient(creator); // self-redirect = veto
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert(RoomFeeSplitter.NoPendingProposal.selector);
        splitter.executeProposedCreatorRecipient();
    }

    function test_operatorRotationOnlyBySafe() public {
        address nextOp = makeAddr("nextOperator");
        vm.expectRevert(RoomFeeSplitter.NotRegistryOwner.selector);
        splitter.setOperator(nextOp);
        vm.prank(platformSafe);
        splitter.setOperator(nextOp);
    }

    function test_claimRoomFundRevertsWhenRegistryUnset() public {
        openTrading();
        buy(makeAddr("whale"), 1_000_000_000);
        splitter.collectQuote();
        vm.prank(platformSafe);
        registry.setRecipients(ROOM_ID, address(0), address(0));
        vm.expectRevert(RoomFeeSplitter.RecipientUnset.selector);
        splitter.claim(Leg.RoomFund);
    }

    function test_registerPositionOnceAndOnlyDeployer() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(RoomFeeSplitter.NotDeployer.selector);
        splitter.registerPosition(1);
        vm.expectRevert(RoomFeeSplitter.PositionAlreadySet.selector);
        splitter.registerPosition(positionId);
    }
}
