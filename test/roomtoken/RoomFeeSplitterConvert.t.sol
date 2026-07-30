// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Harness} from "./Harness.t.sol";
import {RoomFeeSplitter, Leg} from "../../src/roomtoken/RoomFeeSplitter.sol";
import {TickMath} from "../../src/roomtoken/libraries/TickMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RoomFeeSplitterConvertTest is Harness {
    function setUp() public {
        setUpHarness();
        openTrading();
    }

    function _accrueTokenFees() internal {
        // Buys accrue USDG-side fees; sells accrue token-side fees.
        address whale = makeAddr("whale");
        buy(whale, 5_000_000_000); // $5,000
        sell(whale, token.balanceOf(whale) / 2);
        // Let the oracle window fill with post-trade observations.
        vm.warp(block.timestamp + 120);
        buy(makeAddr("second"), 100_000_000); // one more write so observe(60) has both ends
        vm.warp(block.timestamp + 61);
    }

    function test_onlyOperator() public {
        vm.expectRevert(RoomFeeSplitter.NotOperator.selector);
        splitter.convertAndDistribute();
    }

    function test_convertsTokenFeesToQuoteAndCredits() public {
        _accrueTokenFees();
        uint256 before = splitter.ledgerOf(Leg.Creator);
        vm.prank(operator);
        (uint256 tokenIn, uint256 quoteOut) = splitter.convertAndDistribute();
        assertGt(tokenIn, 0);
        assertGt(quoteOut, 0);
        assertGt(splitter.ledgerOf(Leg.Creator), before);
        // Splitter never holds a token bag after conversion.
        assertEq(token.balanceOf(address(splitter)), 0);
    }

    function test_revertsWhenOracleWindowNotElapsed() public {
        // setUp()'s openTrading() already warps ~30min+300s past pool init,
        // so the pool's init observation is always >60s old by the time a
        // test body runs — observe(60) would answer via interpolation
        // against it, never hitting the OLD path. Roll back to just after
        // pool creation (derived from opensAt, set 30 minutes after pool
        // init in setUpHarness) so no 60s-old observation exists yet, and
        // confirm the oracle guard trips before any collection logic runs.
        vm.warp(uint256(opensAt) - 30 minutes + 1);
        vm.prank(operator);
        vm.expectRevert(RoomFeeSplitter.OracleNotReady.selector);
        splitter.convertAndDistribute();
    }

    function test_revertsWithNothingToConvert() public {
        vm.warp(block.timestamp + 120);
        buy(makeAddr("w"), 100_000_000); // fees on quote side only
        vm.warp(block.timestamp + 61);
        vm.prank(operator);
        vm.expectRevert(RoomFeeSplitter.NothingToConvert.selector);
        splitter.convertAndDistribute();
    }

    function test_manipulatedSpotRevertsAndDefers() public {
        _accrueTokenFees();
        // Crash spot far below TWAP within one block. A pure buy-then-
        // sell-everything round trip is fee-bounded to roughly
        // poolFee/(1-poolFee) (~1% for this 1% pool) no matter how large the
        // notional, since the restoring sell always reverses almost all of
        // the impact the buy created — comfortably inside the 2.98% slack,
        // so it alone can never breach the guard. The "whale" from
        // _accrueTokenFees still holds the unsold half of its position
        // (tokens already priced into the TWAP, not fresh this block);
        // sweep that pile into the attacker and dump it as a pure
        // one-directional sell with nothing bought back in this block.
        address whale = makeAddr("whale");
        address attacker = makeAddr("attacker");
        uint256 whaleLeftover = token.balanceOf(whale);
        vm.prank(whale);
        token.transfer(attacker, whaleLeftover);
        buy(attacker, 1_000_000_000_000);
        sell(attacker, token.balanceOf(attacker));
        vm.prank(operator);
        vm.expectRevert(); // router slippage revert bubbles
        splitter.convertAndDistribute();
        // Fees remain accrued in the position: a later honest call succeeds.
        vm.warp(block.timestamp + 3600);
        buy(makeAddr("healer"), 25_000_000_000);
        vm.warp(block.timestamp + 61);
        vm.prank(operator);
        (uint256 tokenIn,) = splitter.convertAndDistribute();
        assertGt(tokenIn, 0);
    }

    function test_minOutSlackIsLoadBearing() public {
        // Independently recompute the UNADJUSTED TWAP expectation exactly the
        // way the contract does, from the same oracle state (same block, so
        // observe() returns identical values to what convertAndDistribute
        // will read). Then prove two things at once:
        //   (1) the real swap pays fee + impact: quoteOut < unadjusted;
        //   (2) the guard passed only because of the slack: the slack-adjusted
        //       floor sits at or below quoteOut.
        // Together: a zero-slack minOut (== unadjusted) would have REVERTED.
        _accrueTokenFees();
        uint32[] memory ago = new uint32[](2);
        ago[0] = 60;
        ago[1] = 0;
        (int56[] memory ticks,) = pool.observe(ago);
        int56 delta = ticks[1] - ticks[0];
        int24 avgTick = int24(delta / 60);
        if (delta < 0 && delta % 60 != 0) avgTick--;
        uint160 sqrtTwap = TickMath.getSqrtRatioAtTick(avgTick);

        vm.prank(operator);
        (uint256 tokenIn, uint256 quoteOut) = splitter.convertAndDistribute();

        uint256 unadjusted = Math.mulDiv(Math.mulDiv(tokenIn, 2 ** 96, sqrtTwap), 2 ** 96, sqrtTwap);
        assertGt(tokenIn, 0);
        assertLt(quoteOut, unadjusted);
        uint256 floor = ((unadjusted * 9_900) / 10_000 * (10_000 - 200)) / 10_000;
        assertLe(floor, quoteOut);
    }

    function test_largeAccrualIsChunkedByImpactCap() public {
        // Accrue a big token-side fee inventory via repeated large sells.
        address whale = makeAddr("megaWhale");
        buy(whale, 50_000_000_000); // $50k
        for (uint256 i = 0; i < 5; i++) {
            sell(whale, token.balanceOf(whale) / 4);
            vm.warp(block.timestamp + 30);
        }
        vm.warp(block.timestamp + 61);
        vm.prank(operator);
        (uint256 firstIn,) = splitter.convertAndDistribute();
        // A second conversion still finds inventory: the first was capped.
        vm.warp(block.timestamp + 61);
        vm.prank(operator);
        (uint256 secondIn,) = splitter.convertAndDistribute();
        assertGt(firstIn, 0);
        assertGt(secondIn, 0);
    }
}
