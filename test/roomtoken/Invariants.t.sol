// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Harness} from "./Harness.t.sol";
import {RoomFeeSplitter, Leg} from "../../src/roomtoken/RoomFeeSplitter.sol";
import {RoomTokenFactoryTest} from "./RoomTokenFactory.t.sol";
import {LaunchParams} from "../../src/roomtoken/RoomTokenFactory.sol";
import {INonfungiblePositionManager} from "../../src/roomtoken/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3PoolMinimal} from "../../src/roomtoken/interfaces/IUniswapV3PoolMinimal.sol";

/// Randomized-actor handler: buys, sells, collects, converts, claims — in any
/// order the fuzzer picks. The invariants must hold after every sequence.
contract SplitterHandler is Harness {
    uint256 public totalCredited;
    address[3] internal actors;

    constructor() {
        setUpHarness();
        openTrading();
        actors = [makeAddr("actor1"), makeAddr("actor2"), makeAddr("actor3")];
    }

    function actBuy(uint256 actorSeed, uint256 amount) external {
        address who = actors[actorSeed % 3];
        buy(who, bound(amount, 1_000_000, 10_000_000_000));
    }

    function actSell(uint256 actorSeed, uint256 bps) external {
        address who = actors[actorSeed % 3];
        uint256 bal = token.balanceOf(who);
        if (bal == 0) return;
        sell(who, (bal * bound(bps, 1, 10_000)) / 10_000);
    }

    function actCollectQuote() external {
        totalCredited += splitter.collectQuote();
    }

    function actConvert() external {
        vm.warp(block.timestamp + 61);
        vm.prank(operator);
        try splitter.convertAndDistribute() returns (uint256, uint256 quoteOut) {
            totalCredited += quoteOut;
        } catch {}
    }

    function actClaim(uint256 legSeed) external {
        Leg leg = Leg(legSeed % 3);
        try splitter.claim(leg) {} catch {}
    }

    function actElapse(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 3600));
    }

    function positionLiquidity() external view returns (uint128 liq) {
        (,,,,,,, liq,,,,) = npm.positions(positionId);
    }

    function ledgerTotal() external view returns (uint256) {
        return splitter.ledgerOf(Leg.Creator) + splitter.ledgerOf(Leg.RoomFund) + splitter.ledgerOf(Leg.Platform);
    }

    function claimedTotal() external view returns (uint256) {
        return usdg.balanceOf(creator) + usdg.balanceOf(roomWallet) + usdg.balanceOf(defaultPlatform);
    }

    function tokenBalanceOfSplitter() external view returns (uint256) {
        return token.balanceOf(address(splitter));
    }
}

contract RoomTokenInvariants is Harness {
    SplitterHandler internal handler;
    uint128 internal initialLiquidity;

    function setUp() public {
        handler = new SplitterHandler();
        initialLiquidity = handler.positionLiquidity();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = SplitterHandler.actBuy.selector;
        selectors[1] = SplitterHandler.actSell.selector;
        selectors[2] = SplitterHandler.actCollectQuote.selector;
        selectors[3] = SplitterHandler.actConvert.selector;
        selectors[4] = SplitterHandler.actClaim.selector;
        selectors[5] = SplitterHandler.actElapse.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// SPEC INVARIANT 1: the splitter can never reduce position liquidity.
    function invariant_positionLiquidityNeverDecreases() public view {
        assertGe(handler.positionLiquidity(), initialLiquidity);
    }

    /// SPEC INVARIANT 2: ledger accounting — everything credited is either
    /// still claimable or already paid out; nothing is minted or lost.
    function invariant_ledgerConservation() public view {
        assertEq(handler.ledgerTotal() + handler.claimedTotal(), handler.totalCredited());
    }

    /// SPEC INVARIANT 3: this is NOT a global "splitter never holds tokens"
    /// invariant — any holder can transfer tokens to the splitter at any
    /// time, and an unsolicited external transfer would break the literal
    /// assertion below without indicating a defect. What this actually
    /// asserts is that the handler's own actions (buy/sell/collect/convert/
    /// claim) never leave a token balance behind, i.e. the splitter's
    /// collect->swap conversion path is atomic under every sequence the
    /// fuzzer tries.
    function invariant_conversionLeavesNoTokenBag() public view {
        assertEq(handler.tokenBalanceOfSplitter(), 0);
    }
}

contract LaunchGasTest is RoomTokenFactoryTest {
    function test_gas_launchWithCardinality700() public {
        LaunchParams memory p = _signedParams(0, 0);
        vm.prank(creator);
        uint256 before = gasleft();
        factory.launch(p);
        uint256 used = before - gasleft();
        emit log_named_uint("launch gas (cardinality 700)", used);
        // Spec expectation: cardinality growth (~700 slots x ~20k) dominates.
        // This is a measurement, not an assertion — record it in Task 8's
        // deployment notes. Assert only a sanity ceiling:
        assertLt(used, 30_000_000);
    }
}
