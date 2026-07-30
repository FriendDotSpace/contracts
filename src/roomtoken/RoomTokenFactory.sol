// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {RoomToken} from "./RoomToken.sol";
import {RoomFeeSplitter, SplitterParams} from "./RoomFeeSplitter.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {ISwapRouterMinimal} from "./interfaces/ISwapRouterMinimal.sol";
import {IUniswapV3PoolMinimal} from "./interfaces/IUniswapV3PoolMinimal.sol";
import {TickMath} from "./libraries/TickMath.sol";

struct LaunchConfig {
    uint96 launchFeeQuote;
    uint16 creatorBps;
    uint16 roomFundBps;
    uint16 platformBps;
    int24 initTick;
    uint32 capWindowSecs;
    uint16 walletCapBps;
    uint32 minCountdownSecs;
    uint32 maxCountdownSecs;
    uint16 cardinalityTarget;
    uint32 twapWindowSecs;
    uint16 maxConversionDeviationBps;
    uint16 maxConversionImpactBps;
}

struct LaunchParams {
    uint256 roomId;
    uint32 configId;
    string name;
    string symbol;
    uint64 tradingOpensAt;
    uint64 deadline;
    bytes32 salt;
    uint256 devBuyQuoteIn;
    uint256 devBuyMinOut;
    bytes authoritySignature;
    bool usePermit;
    uint256 permitValue;
    uint256 permitDeadline;
    uint8 permitV;
    bytes32 permitR;
    bytes32 permitS;
}

interface IRegistryRecipients {
    function recipientsOf(uint256 roomId) external view returns (address roomFund, address platform);
}

/// Holds RoomToken's creation code OUT of the factory's runtime bytecode
/// (EIP-170): deployed once by the factory's constructor — constructor-only
/// code never enters runtime — and callable only by the factory. CREATE2
/// addresses derive from THIS contract's address; off-chain salt mining must
/// target it (exposed as factory.tokenDeployer()).
contract RoomTokenDeployer {
    address public immutable factory;

    error NotFactory();

    constructor() {
        factory = msg.sender;
    }

    function deploy(
        bytes32 salt,
        string calldata name,
        string calldata symbol,
        uint256 roomId,
        address tokenFactory,
        uint64 tradingOpensAt,
        uint32 capWindowSecs,
        uint16 walletCapBps
    ) external returns (address) {
        if (msg.sender != factory) revert NotFactory();
        return address(
            new RoomToken{salt: salt}(name, symbol, roomId, tokenFactory, tradingOpensAt, capWindowSecs, walletCapBps)
        );
    }
}

/// One creator-sent transaction: deploy token (CREATE2, ordering-enforced),
/// create + initialize the pool, grow the oracle, deploy the splitter, seed
/// the full-supply single-sided position into it, run at most one authorized
/// dev buy, finalize the token. Everything economic is pinned by the
/// authority's EIP-712 signature before any of it can run.
contract RoomTokenFactory is Ownable, EIP712 {
    using SafeERC20 for IERC20;

    bytes32 private constant LAUNCH_TYPEHASH = keccak256(
        "Launch(uint256 roomId,address creator,bytes32 economicsHash,uint64 tradingOpensAt,uint64 deadline,bytes32 salt)"
    );
    uint24 public constant POOL_FEE = 10000;
    int24 public constant TICK_LOWER = -887200;
    uint256 private constant Q96 = 2 ** 96;

    IERC20 public immutable quote;
    INonfungiblePositionManager public immutable npm;
    ISwapRouterMinimal public immutable swapRouter;
    address public immutable v3Factory;
    IRegistryRecipients public immutable registry;

    address public authority;
    address public defaultOperator;
    address public immutable tokenDeployer;
    LaunchConfig[] private _configs;
    mapping(uint256 roomId => address token) public tokenOf;

    error UnknownConfig();
    error RoomAlreadyLaunched();
    error CountdownOutOfBounds();
    error AuthorizationExpired();
    error BadAuthoritySignature();
    error TokenOrderingBroken();
    error PermitValueMismatch();
    error PoolPriceMismatch();

    event RoomTokenLaunched(
        uint256 indexed roomId,
        address token,
        address pool,
        address splitter,
        address creator,
        uint32 configId,
        uint64 tradingOpensAt
    );
    event ConfigAppended(uint32 indexed configId);
    event AuthoritySet(address authority);
    event DefaultOperatorSet(address operator);

    constructor(
        address owner_,
        address authority_,
        address defaultOperator_,
        address quote_,
        address npm_,
        address swapRouter_,
        address v3Factory_,
        address registry_
    ) Ownable(owner_) EIP712("RoomTokenFactory", "1") {
        authority = authority_;
        defaultOperator = defaultOperator_;
        quote = IERC20(quote_);
        npm = INonfungiblePositionManager(npm_);
        swapRouter = ISwapRouterMinimal(swapRouter_);
        v3Factory = v3Factory_;
        registry = IRegistryRecipients(registry_);
        // Constructor-deployed so RoomToken's creation code stays out of this
        // contract's runtime bytecode (EIP-170 headroom).
        tokenDeployer = address(new RoomTokenDeployer());
    }

    // ---------------------------------------------------------------- config

    function appendConfig(LaunchConfig calldata c) external onlyOwner returns (uint32 configId) {
        require(c.creatorBps + c.roomFundBps + c.platformBps == 10_000, "bps");
        _configs.push(c);
        configId = uint32(_configs.length - 1);
        emit ConfigAppended(configId);
    }

    function configCount() external view returns (uint32) {
        return uint32(_configs.length);
    }

    function configAt(uint32 id) external view returns (LaunchConfig memory) {
        if (id >= _configs.length) revert UnknownConfig();
        return _configs[id];
    }

    function setAuthority(address next) external onlyOwner {
        authority = next;
        emit AuthoritySet(next);
    }

    function setDefaultOperator(address next) external onlyOwner {
        defaultOperator = next;
        emit DefaultOperatorSet(next);
    }

    // ---------------------------------------------------------------- launch

    function economicsHash(
        uint32 configId,
        uint256 devBuyQuoteIn,
        uint256 devBuyMinOut,
        string calldata name,
        string calldata symbol
    ) public view returns (bytes32) {
        if (configId >= _configs.length) revert UnknownConfig();
        LaunchConfig memory c = _configs[configId];
        return keccak256(
            abi.encode(
                configId,
                c.launchFeeQuote,
                c.creatorBps,
                c.roomFundBps,
                c.platformBps,
                c.initTick,
                c.capWindowSecs,
                c.walletCapBps,
                devBuyQuoteIn,
                devBuyMinOut,
                name,
                symbol
            )
        );
    }

    function launch(LaunchParams calldata p)
        external
        returns (address tokenAddr, address poolAddr, address splitterAddr)
    {
        LaunchConfig memory c = _configAt(p.configId);
        if (tokenOf[p.roomId] != address(0)) revert RoomAlreadyLaunched();
        if (block.timestamp > p.deadline) revert AuthorizationExpired();
        if (
            p.tradingOpensAt < block.timestamp + c.minCountdownSecs
                || p.tradingOpensAt > block.timestamp + c.maxCountdownSecs
        ) revert CountdownOutOfBounds();

        _verifyAuthority(p);
        _pullFunds(p, c);

        // Token: CREATE2 via the deployer child with the signed salt; ordering
        // enforced here, never mined here.
        RoomToken token = RoomToken(
            RoomTokenDeployer(tokenDeployer).deploy(
                p.salt, p.name, p.symbol, p.roomId, address(this), p.tradingOpensAt, c.capWindowSecs, c.walletCapBps
            )
        );
        if (address(token) <= address(quote)) revert TokenOrderingBroken();
        tokenAddr = address(token);
        tokenOf[p.roomId] = tokenAddr;

        // Pool at the config's tick; USDG is token0 by the ordering guarantee.
        uint160 sqrtInit = TickMath.getSqrtRatioAtTick(c.initTick);
        poolAddr = npm.createAndInitializePoolIfNecessary(address(quote), tokenAddr, POOL_FEE, sqrtInit);
        // An attacker who pre-creates+initializes this pool at a different
        // price cannot be undone by createAndInitializePoolIfNecessary (it is
        // a no-op if already initialized) — fail the launch cleanly instead
        // of proceeding with a mint against the wrong price.
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3PoolMinimal(poolAddr).slot0();
        if (sqrtPriceX96 != sqrtInit) revert PoolPriceMismatch();
        IUniswapV3PoolMinimal(poolAddr).increaseObservationCardinalityNext(c.cardinalityTarget);

        splitterAddr = address(
            new RoomFeeSplitter(
                SplitterParams({
                    npm: address(npm),
                    swapRouter: address(swapRouter),
                    pool: poolAddr,
                    token: tokenAddr,
                    quote: address(quote),
                    roomId: p.roomId,
                    registry: address(registry),
                    creatorRecipient: msg.sender,
                    operator: defaultOperator,
                    creatorBps: c.creatorBps,
                    roomFundBps: c.roomFundBps,
                    platformBps: c.platformBps,
                    twapWindowSecs: c.twapWindowSecs,
                    maxConversionDeviationBps: c.maxConversionDeviationBps,
                    maxConversionImpactBps: c.maxConversionImpactBps
                })
            )
        );

        uint128 devBuyMaxOut = p.devBuyQuoteIn == 0
            ? 0
            : SafeCast.toUint128(Math.mulDiv(Math.mulDiv(p.devBuyQuoteIn, sqrtInit, Q96), sqrtInit, Q96));
        token.initializeLaunch(poolAddr, splitterAddr, msg.sender, devBuyMaxOut);

        // Seed the full supply as a single-sided position owned by the splitter.
        token.approve(address(npm), token.TOTAL_SUPPLY());
        (uint256 positionId,,,) = npm.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(quote),
                token1: tokenAddr,
                fee: POOL_FEE,
                tickLower: TICK_LOWER,
                tickUpper: c.initTick,
                amount0Desired: 0,
                amount1Desired: token.TOTAL_SUPPLY(),
                amount0Min: 0,
                amount1Min: 0,
                recipient: splitterAddr,
                deadline: block.timestamp
            })
        );
        RoomFeeSplitter(splitterAddr).registerPosition(positionId);

        if (p.devBuyQuoteIn > 0) {
            quote.forceApprove(address(swapRouter), p.devBuyQuoteIn);
            swapRouter.exactInputSingle(
                ISwapRouterMinimal.ExactInputSingleParams({
                    tokenIn: address(quote),
                    tokenOut: tokenAddr,
                    fee: POOL_FEE,
                    recipient: msg.sender,
                    deadline: block.timestamp,
                    amountIn: p.devBuyQuoteIn,
                    amountOutMinimum: p.devBuyMinOut,
                    sqrtPriceLimitX96: 0
                })
            );
        }

        token.finalizeLaunch();

        // Launch fee to the platform leg (registry falls back to the default).
        (, address platformRecipient) = registry.recipientsOf(p.roomId);
        quote.safeTransfer(platformRecipient, c.launchFeeQuote);

        emit RoomTokenLaunched(p.roomId, tokenAddr, poolAddr, splitterAddr, msg.sender, p.configId, p.tradingOpensAt);
    }

    function _configAt(uint32 id) internal view returns (LaunchConfig memory) {
        if (id >= _configs.length) revert UnknownConfig();
        return _configs[id];
    }

    function _verifyAuthority(LaunchParams calldata p) internal view {
        bytes32 structHash = keccak256(
            abi.encode(
                LAUNCH_TYPEHASH,
                p.roomId,
                msg.sender,
                economicsHash(p.configId, p.devBuyQuoteIn, p.devBuyMinOut, p.name, p.symbol),
                p.tradingOpensAt,
                p.deadline,
                p.salt
            )
        );
        address signer = ECDSA.recover(_hashTypedDataV4(structHash), p.authoritySignature);
        if (signer != authority || authority == address(0)) revert BadAuthoritySignature();
    }

    function _pullFunds(LaunchParams calldata p, LaunchConfig memory c) internal {
        uint256 total = uint256(c.launchFeeQuote) + p.devBuyQuoteIn;
        if (p.usePermit) {
            if (p.permitValue < total) revert PermitValueMismatch();
            // Front-running a permit only wastes the attacker's gas; tolerate
            // a griefed permit by falling through to allowance.
            try IERC20Permit(address(quote)).permit(
                msg.sender, address(this), p.permitValue, p.permitDeadline, p.permitV, p.permitR, p.permitS
            ) {} catch {}
        }
        quote.safeTransferFrom(msg.sender, address(this), total);
    }
}
