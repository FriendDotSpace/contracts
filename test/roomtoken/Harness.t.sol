// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Deployer} from "./UniswapV3Deployer.sol";
import {RoomToken} from "../../src/roomtoken/RoomToken.sol";
import {RoomFeeSplitter, SplitterParams, Leg} from "../../src/roomtoken/RoomFeeSplitter.sol";
import {RoomRecipientRegistry} from "../../src/roomtoken/RoomRecipientRegistry.sol";
import {INonfungiblePositionManager} from "../../src/roomtoken/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouterMinimal} from "../../src/roomtoken/interfaces/ISwapRouterMinimal.sol";
import {IUniswapV3PoolMinimal} from "../../src/roomtoken/interfaces/IUniswapV3PoolMinimal.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockUSDG is ERC20, ERC20Permit {
    constructor() ERC20("Global Dollar", "USDG") ERC20Permit("Global Dollar") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Harness is UniswapV3Deployer {
    int24 internal constant INIT_TICK = 400600;
    int24 internal constant TICK_LOWER = -887200;
    uint24 internal constant FEE = 10000;
    uint32 internal constant WINDOW = 300;
    uint16 internal constant CAP_BPS = 500;
    uint16 internal constant DEV_BUY_CAP_BPS = 1000;

    address internal v3Factory;
    address internal weth9;
    INonfungiblePositionManager internal npm;
    ISwapRouterMinimal internal router;
    MockUSDG internal usdg;
    RoomToken internal token;
    RoomFeeSplitter internal splitter;
    RoomRecipientRegistry internal registry;
    IUniswapV3PoolMinimal internal pool;
    uint256 internal positionId;

    address internal platformSafe = makeAddr("platformSafe");
    address internal defaultPlatform = makeAddr("defaultPlatform");
    address internal roomWallet = makeAddr("roomWallet");
    address internal creator = makeAddr("creator");
    address internal operator = makeAddr("operator");
    uint64 internal opensAt;
    uint256 internal constant ROOM_ID = 42;

    function setUpHarness() internal {
        (address f, address w, address n, address r) = deployAll();
        v3Factory = f;
        weth9 = w;
        npm = INonfungiblePositionManager(n);
        router = ISwapRouterMinimal(r);
        usdg = new MockUSDG();
        registry = new RoomRecipientRegistry(platformSafe, defaultPlatform);
        vm.prank(platformSafe);
        registry.setRecipients(ROOM_ID, roomWallet, address(0));

        opensAt = uint64(block.timestamp + 30 minutes);
        token = _deployTokenAboveQuote();

        // Pool at INIT_TICK; token is token1 by construction.
        uint160 sqrtPrice = _sqrtRatioAtTickViaNpm();
        npm.createAndInitializePoolIfNecessary(address(usdg), address(token), FEE, sqrtPrice);
        pool = IUniswapV3PoolMinimal(IUniswapV3FactoryPools(v3Factory).getPool(address(usdg), address(token), FEE));

        splitter = new RoomFeeSplitter(
            SplitterParams({
                npm: address(npm),
                swapRouter: address(router),
                pool: address(pool),
                token: address(token),
                quote: address(usdg),
                roomId: ROOM_ID,
                registry: address(registry),
                creatorRecipient: creator,
                operator: operator,
                creatorBps: 6000,
                roomFundBps: 2500,
                platformBps: 1500,
                twapWindowSecs: 60,
                maxConversionDeviationBps: 200,
                maxConversionImpactBps: 100
            })
        );

        token.initializeLaunch(address(pool), address(splitter), address(0), 0);
        token.approve(address(npm), type(uint256).max);
        (positionId,,,) = npm.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(usdg),
                token1: address(token),
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: INIT_TICK,
                amount0Desired: 0,
                amount1Desired: token.TOTAL_SUPPLY(),
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(splitter),
                deadline: block.timestamp
            })
        );
        splitter.registerPosition(positionId);
        token.finalizeLaunch();
        IUniswapV3PoolMinimal(address(pool)).increaseObservationCardinalityNext(700);
    }

    /// CREATE2-mine a salt so the token sorts above USDG (USDG stays token0).
    function _deployTokenAboveQuote() internal returns (RoomToken t) {
        bytes memory creation = abi.encodePacked(
            type(RoomToken).creationCode,
            abi.encode("Room 42", "R42", ROOM_ID, address(this), opensAt, WINDOW, CAP_BPS, DEV_BUY_CAP_BPS)
        );
        bytes32 initHash = keccak256(creation);
        for (uint256 i = 0;; i++) {
            bytes32 salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initHash)))));
            if (predicted > address(usdg)) {
                bytes32 s = salt;
                assembly {
                    t := create2(0, add(creation, 0x20), mload(creation), s)
                }
                require(address(t) == predicted, "salt mine mismatch");
                return t;
            }
        }
    }

    /// sqrt price for INIT_TICK, computed once via the vendored TickMath library
    /// (src/roomtoken/libraries/TickMath.sol, official Uniswap v3-core 0.8 port)
    /// and pinned here as a literal. `test_poolInitializedAtInitTick` is the
    /// permanent guard on this constant against the live pool's own slot0.
    function _sqrtRatioAtTickViaNpm() internal pure returns (uint160) {
        // TickMath.getSqrtRatioAtTick(400600)
        return 39569734776372747109332364130380419359;
    }

    function buy(address who, uint256 usdgIn) internal returns (uint256 out) {
        usdg.mint(who, usdgIn);
        vm.startPrank(who);
        usdg.approve(address(router), usdgIn);
        out = router.exactInputSingle(
            ISwapRouterMinimal.ExactInputSingleParams({
                tokenIn: address(usdg),
                tokenOut: address(token),
                fee: FEE,
                recipient: who,
                deadline: block.timestamp,
                amountIn: usdgIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }

    function sell(address who, uint256 tokenIn) internal returns (uint256 out) {
        vm.startPrank(who);
        token.approve(address(router), tokenIn);
        out = router.exactInputSingle(
            ISwapRouterMinimal.ExactInputSingleParams({
                tokenIn: address(token),
                tokenOut: address(usdg),
                fee: FEE,
                recipient: who,
                deadline: block.timestamp,
                amountIn: tokenIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }

    function openTrading() internal {
        vm.warp(uint256(opensAt) + WINDOW + 1);
    }
}

interface IUniswapV3FactoryPools {
    function getPool(address, address, uint24) external view returns (address);
}
