// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Deployer} from "./UniswapV3Deployer.sol";
import {MockUSDG} from "./Harness.t.sol";
import {RoomToken} from "../../src/roomtoken/RoomToken.sol";
import {
    RoomTokenFactory, RoomTokenDeployer, LaunchConfig, LaunchParams
} from "../../src/roomtoken/RoomTokenFactory.sol";
import {RoomFeeSplitter} from "../../src/roomtoken/RoomFeeSplitter.sol";
import {RoomRecipientRegistry} from "../../src/roomtoken/RoomRecipientRegistry.sol";
import {INonfungiblePositionManager} from "../../src/roomtoken/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3PoolMinimal} from "../../src/roomtoken/interfaces/IUniswapV3PoolMinimal.sol";
import {TickMath} from "../../src/roomtoken/libraries/TickMath.sol";

contract RoomTokenFactoryTest is UniswapV3Deployer {
    RoomTokenFactory internal factory;
    RoomRecipientRegistry internal registry;
    MockUSDG internal usdg;
    address internal npmAddr;
    address internal routerAddr;
    address internal v3;

    address internal platformSafe = makeAddr("platformSafe");
    address internal defaultPlatform = makeAddr("defaultPlatform");
    address internal defaultOperator = makeAddr("defaultOperator");
    uint256 internal authorityKey = 0xA11CE;
    address internal authority;
    address internal creator = makeAddr("creator");
    uint256 internal constant ROOM_ID = 42;

    function setUp() public {
        (address f,, address n, address r) = deployAll();
        v3 = f;
        npmAddr = n;
        routerAddr = r;
        usdg = new MockUSDG();
        authority = vm.addr(authorityKey);
        registry = new RoomRecipientRegistry(platformSafe, defaultPlatform);
        factory = new RoomTokenFactory(
            platformSafe, authority, defaultOperator, address(usdg), npmAddr, routerAddr, v3, address(registry)
        );
        vm.prank(platformSafe);
        factory.appendConfig(_defaultConfig());
        usdg.mint(creator, 10_000_000_000); // $10k
        vm.prank(creator);
        usdg.approve(address(factory), type(uint256).max);
    }

    function _defaultConfig() internal pure returns (LaunchConfig memory) {
        return LaunchConfig({
            launchFeeQuote: 1_000_000,
            creatorBps: 6000,
            roomFundBps: 2500,
            platformBps: 1500,
            initTick: 400600,
            capWindowSecs: 300,
            walletCapBps: 500,
            minCountdownSecs: 900,
            maxCountdownSecs: 86400,
            cardinalityTarget: 700,
            twapWindowSecs: 60,
            maxConversionDeviationBps: 200,
            maxConversionImpactBps: 100
        });
    }

    function _mineSalt(string memory name, string memory symbol, uint64 opensAt) internal view returns (bytes32) {
        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(RoomToken).creationCode,
                abi.encode(name, symbol, ROOM_ID, address(factory), opensAt, uint32(300), uint16(500))
            )
        );
        // CREATE2 addresses derive from the factory's deployer child, not the
        // factory itself.
        address deployer = factory.tokenDeployer();
        for (uint256 i = 0;; i++) {
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, bytes32(i), initHash)))));
            if (predicted > address(usdg)) return bytes32(i);
        }
    }

    function _signedParams(uint256 devIn, uint256 devMinOut) internal view returns (LaunchParams memory p) {
        uint64 opensAt = uint64(block.timestamp + 1 hours);
        p.roomId = ROOM_ID;
        p.configId = 0;
        p.name = "Room 42";
        p.symbol = "R42";
        p.tradingOpensAt = opensAt;
        p.deadline = uint64(block.timestamp + 10 minutes);
        p.salt = _mineSalt(p.name, p.symbol, opensAt);
        p.devBuyQuoteIn = devIn;
        p.devBuyMinOut = devMinOut;
        bytes32 digest = _launchDigest(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorityKey, digest);
        p.authoritySignature = abi.encodePacked(r, s, v);
    }

    function _launchDigest(LaunchParams memory p) internal view returns (bytes32) {
        bytes32 typehash = keccak256(
            "Launch(uint256 roomId,address creator,bytes32 economicsHash,uint64 tradingOpensAt,uint64 deadline,bytes32 salt)"
        );
        bytes32 structHash = keccak256(
            abi.encode(
                typehash,
                p.roomId,
                creator,
                factory.economicsHash(p.configId, p.devBuyQuoteIn, p.devBuyMinOut, p.name, p.symbol),
                p.tradingOpensAt,
                p.deadline,
                p.salt
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("RoomTokenFactory")),
                keccak256(bytes("1")),
                block.chainid,
                address(factory)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function test_launchHappyPathNoDevBuy() public {
        LaunchParams memory p = _signedParams(0, 0);
        vm.prank(creator);
        (address tokenAddr, address poolAddr, address splitterAddr) = factory.launch(p);

        RoomToken token = RoomToken(tokenAddr);
        assertEq(token.balanceOf(tokenAddr), 0);
        assertEq(factory.tokenOf(ROOM_ID), tokenAddr);
        assertTrue(token.finalized());
        // Position NFT owned by the splitter.
        assertEq(
            INonfungiblePositionManager(npmAddr).ownerOf(RoomFeeSplitter(splitterAddr).positionTokenId()), splitterAddr
        );
        // Pool sits at initTick with USDG as token0.
        (, int24 tick,,,,,) = IUniswapV3PoolMinimal(poolAddr).slot0();
        assertEq(tick, 400600);
        assertEq(IUniswapV3PoolMinimal(poolAddr).token0(), address(usdg));
        // Cardinality growth requested.
        (,,,, uint16 cardinalityNext,,) = IUniswapV3PoolMinimal(poolAddr).slot0();
        assertEq(cardinalityNext, 700);
        // Launch fee reached the platform recipient.
        assertEq(usdg.balanceOf(defaultPlatform), 1_000_000);
    }

    function test_launchWithDevBuyPaysCreatorWithinBound() public {
        LaunchParams memory p = _signedParams(100_000_000, 1); // $100 dev buy
        vm.prank(creator);
        (address tokenAddr,,) = factory.launch(p);
        RoomToken token = RoomToken(tokenAddr);
        assertGt(token.balanceOf(creator), 0);
        assertTrue(token.devBuyConsumed());
        // Fee + dev buy both left the creator's USDG.
        assertEq(usdg.balanceOf(creator), 10_000_000_000 - 1_000_000 - 100_000_000);
    }

    function test_rejectsSecondLaunchForSameRoom() public {
        LaunchParams memory p = _signedParams(0, 0);
        vm.prank(creator);
        factory.launch(p);
        LaunchParams memory p2 = _signedParams(0, 0);
        vm.prank(creator);
        vm.expectRevert(RoomTokenFactory.RoomAlreadyLaunched.selector);
        factory.launch(p2);
    }

    function test_rejectsTamperedEconomics() public {
        LaunchParams memory p = _signedParams(0, 0);
        p.devBuyQuoteIn = 500_000_000; // tampered after signing
        vm.prank(creator);
        vm.expectRevert(RoomTokenFactory.BadAuthoritySignature.selector);
        factory.launch(p);
    }

    function test_rejectsWrongSigner() public {
        LaunchParams memory p = _signedParams(0, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, _launchDigest(p));
        p.authoritySignature = abi.encodePacked(r, s, v);
        vm.prank(creator);
        vm.expectRevert(RoomTokenFactory.BadAuthoritySignature.selector);
        factory.launch(p);
    }

    function test_rejectsExpiredAuthorization() public {
        LaunchParams memory p = _signedParams(0, 0);
        vm.warp(block.timestamp + 11 minutes);
        vm.prank(creator);
        vm.expectRevert(RoomTokenFactory.AuthorizationExpired.selector);
        factory.launch(p);
    }

    function test_rejectsCountdownOutOfBounds() public {
        LaunchParams memory p = _signedParams(0, 0);
        p.tradingOpensAt = uint64(block.timestamp + 10 minutes); // < 15 min floor
        // re-sign for the altered field
        bytes32 digest = _launchDigest(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorityKey, digest);
        p.authoritySignature = abi.encodePacked(r, s, v);
        vm.prank(creator);
        vm.expectRevert(RoomTokenFactory.CountdownOutOfBounds.selector);
        factory.launch(p);
    }

    function test_rejectsBadSaltOrdering() public {
        LaunchParams memory p = _signedParams(0, 0);
        // find a salt that sorts BELOW usdg and re-sign
        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(RoomToken).creationCode,
                abi.encode(p.name, p.symbol, ROOM_ID, address(factory), p.tradingOpensAt, uint32(300), uint16(500))
            )
        );
        address deployer = factory.tokenDeployer();
        for (uint256 i = 0;; i++) {
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, bytes32(i), initHash)))));
            if (predicted < address(usdg)) {
                p.salt = bytes32(i);
                break;
            }
        }
        bytes32 digest = _launchDigest(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorityKey, digest);
        p.authoritySignature = abi.encodePacked(r, s, v);
        vm.prank(creator);
        vm.expectRevert(RoomTokenFactory.TokenOrderingBroken.selector);
        factory.launch(p);
    }

    function test_permitPathNeedsNoPriorApproval() public {
        // fresh creator with no approve
        uint256 pk = 0xC0FFEE;
        address fresh = vm.addr(pk);
        usdg.mint(fresh, 2_000_000);
        LaunchParams memory p;
        {
            // reuse the standard builder but for the fresh creator
            uint64 opensAt = uint64(block.timestamp + 1 hours);
            p.roomId = 77;
            p.configId = 0;
            p.name = "Room 77";
            p.symbol = "R77";
            p.tradingOpensAt = opensAt;
            p.deadline = uint64(block.timestamp + 10 minutes);
            bytes32 initHash = keccak256(
                abi.encodePacked(
                    type(RoomToken).creationCode,
                    abi.encode(p.name, p.symbol, uint256(77), address(factory), opensAt, uint32(300), uint16(500))
                )
            );
            address deployer = factory.tokenDeployer();
            for (uint256 i = 0;; i++) {
                address predicted =
                    address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, bytes32(i), initHash)))));
                if (predicted > address(usdg)) {
                    p.salt = bytes32(i);
                    break;
                }
            }
            bytes32 typehash = keccak256(
                "Launch(uint256 roomId,address creator,bytes32 economicsHash,uint64 tradingOpensAt,uint64 deadline,bytes32 salt)"
            );
            bytes32 structHash = keccak256(
                abi.encode(
                    typehash,
                    uint256(77),
                    fresh,
                    factory.economicsHash(0, 0, 0, p.name, p.symbol),
                    p.tradingOpensAt,
                    p.deadline,
                    p.salt
                )
            );
            bytes32 ds = keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("RoomTokenFactory")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(factory)
                )
            );
            (uint8 av, bytes32 ar, bytes32 as_) =
                vm.sign(authorityKey, keccak256(abi.encodePacked("\x19\x01", ds, structHash)));
            p.authoritySignature = abi.encodePacked(ar, as_, av);
        }
        // USDG permit signed by the fresh creator
        p.usePermit = true;
        p.permitValue = 1_000_000;
        p.permitDeadline = block.timestamp + 10 minutes;
        bytes32 permitDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                usdg.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        fresh,
                        address(factory),
                        uint256(1_000_000),
                        usdg.nonces(fresh),
                        p.permitDeadline
                    )
                )
            )
        );
        (p.permitV, p.permitR, p.permitS) = vm.sign(pk, permitDigest);
        vm.prank(fresh);
        factory.launch(p);
        assertEq(factory.tokenOf(77) == address(0), false);
    }

    function test_deployerRejectsNonFactoryCaller() public {
        RoomTokenDeployer deployer = RoomTokenDeployer(factory.tokenDeployer());
        vm.expectRevert(RoomTokenDeployer.NotFactory.selector);
        deployer.deploy(bytes32(0), "X", "X", 999, address(factory), uint64(block.timestamp + 1 hours), 300, 500);
    }

    function test_rejectsPermitValueBelowFeePlusDevBuy() public {
        LaunchParams memory p = _signedParams(100_000_000, 1); // $100 dev buy signed
        p.usePermit = true;
        p.permitValue = 1_000_000; // covers only the launch fee, not + devBuyQuoteIn
        p.permitDeadline = block.timestamp + 10 minutes;
        // The value check fires before the permit call, so a dummy signature
        // is sufficient — it must never be reached.
        p.permitV = 27;
        p.permitR = bytes32(uint256(1));
        p.permitS = bytes32(uint256(1));
        vm.prank(creator);
        vm.expectRevert(RoomTokenFactory.PermitValueMismatch.selector);
        factory.launch(p);
    }

    /// A griefer who predicts the CREATE2 token address for a signed launch
    /// and pre-creates+initializes the pool at a different price must turn
    /// the launch into a clean revert, not a broken mint against the wrong
    /// price.
    function test_launchRevertsWhenPoolPreInitializedAtWrongPrice() public {
        LaunchParams memory p = _signedParams(0, 0);

        // Predict the CREATE2 token address for this salt against the
        // deployer child (never the factory address itself).
        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(RoomToken).creationCode,
                abi.encode(p.name, p.symbol, ROOM_ID, address(factory), p.tradingOpensAt, uint32(300), uint16(500))
            )
        );
        address deployerAddr = factory.tokenDeployer();
        address predictedToken =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployerAddr, p.salt, initHash)))));
        assertGt(uint160(predictedToken), uint160(address(usdg)));

        // Pre-create + initialize the (usdg, predictedToken, 1%) pool at a
        // DIFFERENT tick than the config's initTick (400600).
        uint160 attackerSqrtPrice = TickMath.getSqrtRatioAtTick(400000);
        INonfungiblePositionManager(npmAddr).createAndInitializePoolIfNecessary(
            address(usdg), predictedToken, 10000, attackerSqrtPrice
        );

        vm.prank(creator);
        vm.expectRevert(RoomTokenFactory.PoolPriceMismatch.selector);
        factory.launch(p);
    }

    /// The config existence check runs before signature verification (the
    /// very first line of `launch`), so an unknown configId reverts
    /// UnknownConfig regardless of what the signature covers.
    function test_launchRevertsOnUnknownConfig() public {
        LaunchParams memory p = _signedParams(0, 0);
        p.configId = 1; // only config 0 was appended in setUp
        // The config check fires before signature verification, so a bogus
        // signature (left over from configId=0) is never even reached.
        vm.prank(creator);
        vm.expectRevert(RoomTokenFactory.UnknownConfig.selector);
        factory.launch(p);
    }

    /// Countdown upper bound: tradingOpensAt more than 24h out must revert,
    /// mirroring the existing lower-bound test.
    function test_rejectsCountdownOverUpperBound() public {
        LaunchParams memory p = _signedParams(0, 0);
        p.tradingOpensAt = uint64(block.timestamp + 86401); // > 24h ceiling
        // re-sign for the altered field
        bytes32 digest = _launchDigest(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorityKey, digest);
        p.authoritySignature = abi.encodePacked(r, s, v);
        vm.prank(creator);
        vm.expectRevert(RoomTokenFactory.CountdownOutOfBounds.selector);
        factory.launch(p);
    }
}
