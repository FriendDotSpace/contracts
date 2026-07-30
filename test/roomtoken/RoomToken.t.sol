// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RoomToken} from "../../src/roomtoken/RoomToken.sol";

contract RoomTokenTest is Test {
    RoomToken internal token;
    address internal factory = makeAddr("factory");
    address internal pool = makeAddr("pool");
    address internal splitter = makeAddr("splitter");
    address internal creator = makeAddr("creator");
    address internal buyer = makeAddr("buyer");
    uint64 internal opensAt;

    uint32 internal constant WINDOW = 300;
    uint16 internal constant CAP_BPS = 500;

    function setUp() public {
        opensAt = uint64(block.timestamp + 1 hours);
        vm.prank(factory);
        token = new RoomToken("Room 42", "R42", 42, factory, opensAt, WINDOW, CAP_BPS);
    }

    function _initialize(uint128 devMax) internal {
        vm.prank(factory);
        token.initializeLaunch(pool, splitter, creator, devMax);
    }

    function test_mintsFullSupplyToFactory() public view {
        assertEq(token.totalSupply(), 1_000_000_000e18);
        assertEq(token.balanceOf(factory), 1_000_000_000e18);
    }

    function test_preFinalize_allowsFactoryToPoolViaTransferFrom() public {
        _initialize(0);
        // NPM pattern: an arbitrary caller moves factory -> pool with allowance
        address npm = makeAddr("npm");
        vm.prank(factory);
        token.approve(npm, type(uint256).max);
        vm.prank(npm);
        token.transferFrom(factory, pool, 1_000_000_000e18);
        assertEq(token.balanceOf(pool), 1_000_000_000e18);
    }

    function test_preFinalize_blocksFactoryToAnyoneElse() public {
        _initialize(0);
        vm.prank(factory);
        vm.expectRevert(RoomToken.PreOpenTransferForbidden.selector);
        token.transfer(buyer, 1);
    }

    function test_preFinalize_allowsSingleBoundedDevBuyThenConsumes() public {
        _initialize(100e18);
        // seed the pool as the position mint would
        address npm = makeAddr("npm");
        vm.prank(factory);
        token.approve(npm, type(uint256).max);
        vm.prank(npm);
        token.transferFrom(factory, pool, 1_000_000_000e18);

        vm.prank(pool);
        token.transfer(creator, 100e18);
        assertTrue(token.devBuyConsumed());

        vm.prank(pool);
        vm.expectRevert(RoomToken.PreOpenTransferForbidden.selector);
        token.transfer(creator, 1);
    }

    function test_preFinalize_devBuyOverMaxReverts() public {
        _initialize(100e18);
        vm.prank(pool);
        vm.expectRevert(RoomToken.DevBuyNotAuthorized.selector);
        token.transfer(creator, 100e18 + 1);
    }

    function test_gated_blocksAllTransfersUntilOpen() public {
        _initialize(0);
        _finalize();
        vm.prank(pool);
        vm.expectRevert(RoomToken.TransferNotAllowedYet.selector);
        token.transfer(buyer, 1);
    }

    function test_window_capsRecipientBalance() public {
        _initialize(0);
        _seedPoolAndFinalize();
        vm.warp(opensAt);
        uint256 cap = (token.TOTAL_SUPPLY() * CAP_BPS) / 10_000;
        vm.prank(pool);
        token.transfer(buyer, cap);
        vm.prank(pool);
        vm.expectRevert(RoomToken.WalletCapExceeded.selector);
        token.transfer(buyer, 1);
    }

    function test_window_poolAndSplitterExemptAsRecipients() public {
        _initialize(0);
        _seedPoolAndFinalize();
        vm.warp(opensAt);
        uint256 cap = (token.TOTAL_SUPPLY() * CAP_BPS) / 10_000;
        vm.prank(pool);
        token.transfer(buyer, cap);
        // a sell (buyer -> pool) must work even though pool holds >> cap
        vm.prank(buyer);
        token.transfer(pool, cap);
        assertEq(token.balanceOf(buyer), 0);
    }

    function test_afterWindow_unrestricted() public {
        _initialize(0);
        _seedPoolAndFinalize();
        vm.warp(opensAt + WINDOW);
        uint256 tenPct = token.TOTAL_SUPPLY() / 10;
        vm.prank(pool);
        token.transfer(buyer, tenPct);
        assertEq(token.balanceOf(buyer), tenPct);
    }

    function test_onlyFactoryCanInitializeAndFinalize() public {
        vm.expectRevert(RoomToken.NotFactory.selector);
        token.initializeLaunch(pool, splitter, creator, 0);
        _initialize(0);
        vm.expectRevert(RoomToken.NotFactory.selector);
        token.finalizeLaunch();
    }

    function test_finalizeIsIrreversibleAndSingleUse() public {
        _initialize(0);
        _finalize();
        vm.prank(factory);
        vm.expectRevert(RoomToken.AlreadyFinalized.selector);
        token.finalizeLaunch();
    }

    function test_finalizeMustFollowInitialize() public {
        // Finalize before initialize reverts NotInitialized
        vm.prank(factory);
        vm.expectRevert(RoomToken.NotInitialized.selector);
        token.finalizeLaunch();
        // Then initialize succeeds
        _initialize(0);
        // Then finalize succeeds
        _finalize();
    }

    function test_preFinalize_zeroDevBuyDoesNotConsume() public {
        _initialize(100e18);
        // seed the pool
        address npm = makeAddr("npm");
        vm.prank(factory);
        token.approve(npm, type(uint256).max);
        vm.prank(npm);
        token.transferFrom(factory, pool, 1_000_000_000e18);

        // Zero-value transfer reverts DevBuyNotAuthorized and doesn't consume
        vm.prank(pool);
        vm.expectRevert(RoomToken.DevBuyNotAuthorized.selector);
        token.transfer(creator, 0);
        assertFalse(token.devBuyConsumed());

        // The real bounded dev buy still succeeds
        vm.prank(pool);
        token.transfer(creator, 100e18);
        assertTrue(token.devBuyConsumed());
    }

    function _finalize() internal {
        vm.prank(factory);
        token.finalizeLaunch();
    }

    function _seedPoolAndFinalize() internal {
        address npm = makeAddr("npm");
        vm.prank(factory);
        token.approve(npm, type(uint256).max);
        vm.prank(npm);
        token.transferFrom(factory, pool, 1_000_000_000e18);
        _finalize();
    }

    /// After finalize + window elapse, NO transfer between non-pool EOAs can
    /// revert for state-machine reasons (fuzzed amounts/recipients).
    function testFuzz_afterWindowNoStateMachineReverts(address to, uint96 amount) public {
        vm.assume(to != address(0) && to != pool && to.code.length == 0);
        _initialize(0);
        _seedPoolAndFinalize();
        vm.warp(opensAt + WINDOW + 1);
        uint256 amt = bound(uint256(amount), 1, token.balanceOf(pool));
        vm.prank(pool);
        token.transfer(to, amt);
        assertEq(token.balanceOf(to), amt);
    }

    /// The cap can never lock the pool out of RECEIVING (sells always work).
    function testFuzz_sellsAlwaysAllowedDuringWindow(uint96 amount) public {
        _initialize(0);
        _seedPoolAndFinalize();
        vm.warp(opensAt);
        uint256 cap = (token.TOTAL_SUPPLY() * CAP_BPS) / 10_000;
        uint256 buyAmt = bound(uint256(amount), 1, cap);
        vm.prank(pool);
        token.transfer(buyer, buyAmt);
        vm.prank(buyer);
        token.transfer(pool, buyAmt);
        assertEq(token.balanceOf(buyer), 0);
    }
}
