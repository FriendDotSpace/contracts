// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {ISwapRouterMinimal} from "./interfaces/ISwapRouterMinimal.sol";
import {IUniswapV3PoolMinimal} from "./interfaces/IUniswapV3PoolMinimal.sol";
import {TickMath} from "./libraries/TickMath.sol";

enum Leg {
    Creator,
    RoomFund,
    Platform
}

struct SplitterParams {
    address npm;
    address swapRouter;
    address pool;
    address token;
    address quote;
    uint256 roomId;
    address registry;
    address creatorRecipient;
    address operator;
    uint16 creatorBps;
    uint16 roomFundBps;
    uint16 platformBps;
    uint32 twapWindowSecs;
    uint16 maxConversionDeviationBps;
    uint16 maxConversionImpactBps;
}

interface IRegistryView {
    function recipientsOf(uint256 roomId) external view returns (address roomFund, address platform);
    function owner() external view returns (address);
}

/// Owns the locked LP position. INVARIANT: no code path in this contract can
/// reduce position liquidity or move the NFT out — there is deliberately no
/// decreaseLiquidity, no burn, no NFT transfer, no delegatecall, no upgrade.
/// A worst-case bug here caps at fees accrued since the last collection.
contract RoomFeeSplitter is IERC721Receiver {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint64 private constant PROPOSAL_DELAY = 3 days;
    uint64 private constant PROPOSAL_WINDOW = 7 days;
    uint24 private constant POOL_FEE_BPS = 100; // 1% tier expressed in bps

    INonfungiblePositionManager public immutable npm;
    ISwapRouterMinimal public immutable swapRouter;
    IUniswapV3PoolMinimal public immutable pool;
    IERC20 public immutable token;
    IERC20 public immutable quote;
    uint256 public immutable roomId;
    IRegistryView public immutable registry;
    address public immutable deployer;
    uint16 public immutable creatorBps;
    uint16 public immutable roomFundBps;
    uint16 public immutable platformBps;
    uint32 public immutable twapWindowSecs;
    uint16 public immutable maxConversionDeviationBps;
    uint16 public immutable maxConversionImpactBps;

    uint256 public positionTokenId;
    bool public positionSet;
    address public creatorRecipient;
    address public operator;

    struct Proposal {
        address candidate;
        uint64 eta;
        uint64 expiry;
    }

    Proposal public pendingCreatorProposal;

    mapping(Leg => uint256) private _ledger;

    error NotDeployer();
    error PositionAlreadySet();
    error PositionNotSet();
    error PositionNotOwned();
    error FeeTierMismatch();
    error NotCreatorRecipient();
    error NotRegistryOwner();
    error NotOperator();
    error NoPendingProposal();
    error ProposalNotReady();
    error ProposalExpired();
    error RecipientUnset();
    error NothingToClaim();
    error OracleNotReady();
    error NothingToConvert();

    event QuoteCollected(uint256 amount);
    event Credited(uint256 creatorAmt, uint256 roomFundAmt, uint256 platformAmt);
    event Claimed(Leg leg, address recipient, uint256 amount);
    event CreatorRecipientSet(address recipient);
    event CreatorRecipientProposed(address candidate, uint64 eta, uint64 expiry);
    event OperatorSet(address operator);
    event Converted(uint256 tokenIn, uint256 quoteOut);

    constructor(SplitterParams memory p) {
        require(p.creatorBps + p.roomFundBps + p.platformBps == BPS, "bps");
        npm = INonfungiblePositionManager(p.npm);
        swapRouter = ISwapRouterMinimal(p.swapRouter);
        pool = IUniswapV3PoolMinimal(p.pool);
        // The hardcoded POOL_FEE_BPS=100 slack in convertAndDistribute is only
        // sound for the 1% tier — refuse to custody a position in any other
        // tier's pool.
        if (pool.fee() != 10_000) revert FeeTierMismatch();
        token = IERC20(p.token);
        quote = IERC20(p.quote);
        roomId = p.roomId;
        registry = IRegistryView(p.registry);
        deployer = msg.sender;
        creatorRecipient = p.creatorRecipient;
        operator = p.operator;
        creatorBps = p.creatorBps;
        roomFundBps = p.roomFundBps;
        platformBps = p.platformBps;
        twapWindowSecs = p.twapWindowSecs;
        maxConversionDeviationBps = p.maxConversionDeviationBps;
        maxConversionImpactBps = p.maxConversionImpactBps;
        emit CreatorRecipientSet(p.creatorRecipient);
        emit OperatorSet(p.operator);
    }

    // ---------------------------------------------------------------- custody

    function registerPosition(uint256 tokenId) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (positionSet) revert PositionAlreadySet();
        if (npm.ownerOf(tokenId) != address(this)) revert PositionNotOwned();
        positionSet = true;
        positionTokenId = tokenId;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // ------------------------------------------------------------- collection

    /// Collects only the USDG (token0) side of accrued fees. Safe for anyone:
    /// no swap, recipients fixed, split immutable.
    function collectQuote() external returns (uint256 quoteCollected) {
        if (!positionSet) revert PositionNotSet();
        (quoteCollected,) = npm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: 0
            })
        );
        if (quoteCollected > 0) {
            _credit(quoteCollected);
            emit QuoteCollected(quoteCollected);
        }
    }

    function _credit(uint256 amount) internal {
        uint256 c = (amount * creatorBps) / BPS;
        uint256 f = (amount * roomFundBps) / BPS;
        uint256 p = amount - c - f; // platform absorbs rounding dust
        _ledger[Leg.Creator] += c;
        _ledger[Leg.RoomFund] += f;
        _ledger[Leg.Platform] += p;
        emit Credited(c, f, p);
    }

    // ------------------------------------------------------------------ claims

    function ledgerOf(Leg leg) external view returns (uint256) {
        return _ledger[leg];
    }

    function claim(Leg leg) external returns (uint256 amount) {
        amount = _ledger[leg];
        if (amount == 0) revert NothingToClaim();
        address recipient = _resolve(leg);
        if (recipient == address(0)) revert RecipientUnset();
        _ledger[leg] = 0;
        quote.safeTransfer(recipient, amount);
        emit Claimed(leg, recipient, amount);
    }

    function _resolve(Leg leg) internal view returns (address) {
        if (leg == Leg.Creator) return creatorRecipient;
        (address roomFund, address platform) = registry.recipientsOf(roomId);
        return leg == Leg.RoomFund ? roomFund : platform;
    }

    // -------------------------------------------------------------- redirects

    function setCreatorRecipient(address next) external {
        if (msg.sender != creatorRecipient) revert NotCreatorRecipient();
        creatorRecipient = next;
        delete pendingCreatorProposal;
        emit CreatorRecipientSet(next);
    }

    function proposeCreatorRecipient(address candidate) external {
        if (msg.sender != registry.owner()) revert NotRegistryOwner();
        uint64 eta = uint64(block.timestamp) + PROPOSAL_DELAY;
        pendingCreatorProposal = Proposal(candidate, eta, eta + PROPOSAL_WINDOW);
        emit CreatorRecipientProposed(candidate, eta, eta + PROPOSAL_WINDOW);
    }

    function executeProposedCreatorRecipient() external {
        Proposal memory prop = pendingCreatorProposal;
        if (prop.candidate == address(0)) revert NoPendingProposal();
        if (block.timestamp < prop.eta) revert ProposalNotReady();
        if (block.timestamp >= prop.expiry) revert ProposalExpired();
        creatorRecipient = prop.candidate;
        delete pendingCreatorProposal;
        emit CreatorRecipientSet(prop.candidate);
    }

    function setOperator(address next) external {
        if (msg.sender != registry.owner()) revert NotRegistryOwner();
        operator = next;
        emit OperatorSet(next);
    }

    // ------------------------------------------------------------- conversion

    uint256 private constant Q96 = 2 ** 96;

    /// Collects the token side (bounded by the impact cap) and sells it into
    /// the pool for USDG in the same transaction, guarded by a TWAP-derived
    /// minimum output. Deferral is the failure mode: any revert leaves fees
    /// accrued inside the position, never in this contract.
    function convertAndDistribute() external returns (uint256 tokenIn, uint256 quoteOut) {
        if (msg.sender != operator) revert NotOperator();
        if (!positionSet) revert PositionNotSet();

        uint160 sqrtTwap = _twapSqrtPrice();

        // Impact cap against TWAP-implied token reserve.
        uint256 virtualTokenReserve = Math.mulDiv(pool.liquidity(), sqrtTwap, Q96);
        uint256 cap = (virtualTokenReserve * maxConversionImpactBps) / BPS;
        uint128 amount1Max = cap > type(uint128).max ? type(uint128).max : uint128(cap);
        if (amount1Max == 0) revert NothingToConvert();

        (, tokenIn) = npm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionTokenId,
                recipient: address(this),
                amount0Max: 0,
                amount1Max: amount1Max
            })
        );
        if (tokenIn == 0) revert NothingToConvert();

        uint256 expectedQuoteOut = Math.mulDiv(Math.mulDiv(tokenIn, Q96, sqrtTwap), Q96, sqrtTwap);
        uint256 minOut = (expectedQuoteOut * (BPS - POOL_FEE_BPS)) / BPS;
        minOut = (minOut * (BPS - maxConversionDeviationBps)) / BPS;

        token.forceApprove(address(swapRouter), tokenIn);
        quoteOut = swapRouter.exactInputSingle(
            ISwapRouterMinimal.ExactInputSingleParams({
                tokenIn: address(token),
                tokenOut: address(quote),
                fee: pool.fee(),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: tokenIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            })
        );
        _credit(quoteOut);
        emit Converted(tokenIn, quoteOut);
    }

    function _twapSqrtPrice() internal view returns (uint160) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindowSecs;
        secondsAgos[1] = 0;
        try pool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
            int56 delta = tickCumulatives[1] - tickCumulatives[0];
            int24 avgTick = int24(delta / int56(uint56(twapWindowSecs)));
            // Round toward negative infinity (standard OracleLibrary adjustment).
            if (delta < 0 && (delta % int56(uint56(twapWindowSecs)) != 0)) avgTick--;
            return TickMath.getSqrtRatioAtTick(avgTick);
        } catch {
            revert OracleNotReady();
        }
    }
}
