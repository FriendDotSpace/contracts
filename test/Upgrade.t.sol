// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.27;

// import {Test, console} from "forge-std/Test.sol";
// import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
// import {FriendKey} from "src/FriendKey.sol";
// import {FriendKeyV2} from "src/v2/FriendKeyV2.sol";
// import {FriendRoomManager} from "src/FriendRoomManager.sol";
// import {FriendRoomManagerV2} from "src/v2/FriendRoomManagerV2.sol";
// import {IFriendKey} from "src/interfaces/IFriendKey.sol";
// import {MockERC20, MockPool} from "./FriendKey.t.sol";

// /**
//  * @title UpgradeTest
//  * @notice Comprehensive tests for upgrading FriendKey and FriendRoomManager to V2
//  * @dev Tests:
//  *      - Storage preservation during upgrades
//  *      - New V2 functionality
//  *      - Backward compatibility
//  *      - State migration
//  */
// contract UpgradeTest is Test {
//     FriendKey public friendKeyV1;
//     FriendKeyV2 public friendKeyV2;
//     FriendRoomManager public roomManagerV1;
//     FriendRoomManagerV2 public roomManagerV2;

//     MockERC20 public mockUsdc;
//     address public owner;
//     address public devFeeDestination;
//     address public tradingPoolFeeDestination;
//     address public creatorAccount;
//     address public buyerAccount;

//     uint256 public constant CREATOR_TOKEN_ID = 1;
//     uint256 private constant OWNER_PRIVATE_KEY = 1;
//     bytes32 private constant REGISTER_CREATOR_TYPEHASH =
//         keccak256("RegisterCreator(address account,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)");
//     bytes32 private constant EIP712_DOMAIN_TYPEHASH =
//         keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
//     bytes32 private constant NAME_HASH = keccak256(bytes("FriendKey"));
//     bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

//     function setUp() public {
//         owner = vm.addr(1);
//         devFeeDestination = vm.addr(2);
//         creatorAccount = vm.addr(5);
//         buyerAccount = vm.addr(6);

//         mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
//         MockPool pool = new MockPool(address(mockUsdc));
//         tradingPoolFeeDestination = address(pool);

//         // Deploy FriendStake beacon
//         address friendStakeBeacon = Upgrades.deployBeacon("FriendStake.sol", owner);

//         vm.startPrank(owner);
//         // Deploy V1 RoomManager
//         bytes memory roomManagerInitData = abi.encodeCall(FriendRoomManager.initialize, (owner));
//         address roomManagerProxy = Upgrades.deployUUPSProxy("FriendRoomManager.sol", roomManagerInitData);
//         roomManagerV1 = FriendRoomManager(roomManagerProxy);

//         // Deploy V1 FriendKey
//         bytes memory initializeData =
//             abi.encodeCall(FriendKey.initialize, (owner, address(mockUsdc), friendStakeBeacon, address(roomManagerV1)));
//         address friendKeyProxy = Upgrades.deployUUPSProxy("FriendKey.sol", initializeData);
//         friendKeyV1 = FriendKey(friendKeyProxy);

//         // Link contracts
//         roomManagerV1.setFriendKey(address(friendKeyV1));
//         roomManagerV1.setFeeDestinations(devFeeDestination, tradingPoolFeeDestination);
//         vm.stopPrank();

//         // Register a creator
//         vm.startPrank(creatorAccount);
//         string memory metadata = "";
//         bytes memory signature = _getRegisterCreatorSignature(creatorAccount, FriendKey.RoomTier.Club, 0, metadata);
//         friendKeyV1.registerCreator(metadata, signature);
//         vm.stopPrank();

//         // Mint tokens for testing
//         mockUsdc.mint(creatorAccount, 1_000_000 * (10 ** 6));
//         mockUsdc.mint(buyerAccount, 1_000_000 * (10 ** 6));
//     }

//     // Helper functions
//     function _domainSeparator() internal view returns (bytes32) {
//         return
//             keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(friendKeyV1)));
//     }

//     function _getRegisterCreatorSignature(
//         address account,
//         FriendKey.RoomTier tier,
//         uint256 additionalKeys,
//         string memory metadata
//     ) internal view returns (bytes memory) {
//         uint256 nonce = friendKeyV1.registerCreatorNonces(account);
//         bytes32 metadataHash = keccak256(bytes(metadata));
//         bytes32 structHash =
//             keccak256(abi.encode(REGISTER_CREATOR_TYPEHASH, account, uint8(tier), additionalKeys, nonce, metadataHash));
//         bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PRIVATE_KEY, digest);
//         return abi.encodePacked(r, s, v);
//     }

//     // ============================================
//     // FRIENDKEY UPGRADE TESTS
//     // ============================================

//     function testFriendKeyUpgrade_PreservesStorage() public {
//         // Record V1 state
//         address v1Creator = friendKeyV1.creatorByTokenId(CREATOR_TOKEN_ID);
//         friendKeyV1.bondingCurveReserves(v1Creator);
//         address v1RoomManager = friendKeyV1.roomManager();
//         address v1BondingToken = address(friendKeyV1.bondingToken());
//         uint256 v1Supply = friendKeyV1.totalSupply(CREATOR_TOKEN_ID);

//         // Buy some shares to add to reserve
//         vm.startPrank(buyerAccount);
//         uint256 price = friendKeyV1.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 10);
//         mockUsdc.approve(address(friendKeyV1), price);
//         friendKeyV1.buyShares(CREATOR_TOKEN_ID, 10, 0);
//         vm.stopPrank();

//         uint256 v1ReserveAfterBuy = friendKeyV1.bondingCurveReserves(v1Creator);

//         // Upgrade to V2
//         vm.startPrank(owner);
//         address friendKeyProxy = address(friendKeyV1);
//         Upgrades.upgradeProxy(friendKeyProxy, "FriendKeyV2.sol", "");
//         friendKeyV2 = FriendKeyV2(friendKeyProxy);
//         friendKeyV2.initializeV2();
//         vm.stopPrank();

//         // Verify storage is preserved
//         assertEq(friendKeyV2.creatorByTokenId(CREATOR_TOKEN_ID), v1Creator, "Creator should be preserved");
//         assertEq(friendKeyV2.bondingCurveReserves(v1Creator), v1ReserveAfterBuy, "Reserve should be preserved");
//         assertEq(friendKeyV2.roomManager(), v1RoomManager, "RoomManager should be preserved");
//         assertEq(address(friendKeyV2.bondingToken()), v1BondingToken, "BondingToken should be preserved");
//         assertEq(friendKeyV2.totalSupply(CREATOR_TOKEN_ID), v1Supply + 10, "Supply should be preserved");
//     }

//     function testFriendKeyUpgrade_NewV2Features() public {
//         // Upgrade to V2
//         vm.startPrank(owner);
//         address friendKeyProxy = address(friendKeyV1);
//         Upgrades.upgradeProxy(friendKeyProxy, "FriendKeyV2.sol", "");
//         friendKeyV2 = FriendKeyV2(friendKeyProxy);
//         friendKeyV2.initializeV2();
//         vm.stopPrank();

//         // Test V2 features
//         assertTrue(friendKeyV2.v2FeatureEnabled(), "V2 features should be enabled");

//         // Test setting V2 metadata
//         vm.prank(owner);
//         friendKeyV2.setV2Metadata(CREATOR_TOKEN_ID, "V2 Metadata");
//         assertEq(friendKeyV2.getV2Metadata(CREATOR_TOKEN_ID), "V2 Metadata", "V2 metadata should be set");
//     }

//     function testFriendKeyUpgrade_BackwardCompatibility() public {
//         // Buy shares in V1
//         vm.startPrank(buyerAccount);
//         uint256 price = friendKeyV1.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 5);
//         mockUsdc.approve(address(friendKeyV1), price);
//         friendKeyV1.buyShares(CREATOR_TOKEN_ID, 5, 0);
//         vm.stopPrank();

//         // Upgrade to V2
//         vm.startPrank(owner);
//         address friendKeyProxy = address(friendKeyV1);
//         Upgrades.upgradeProxy(friendKeyProxy, "FriendKeyV2.sol", "");
//         friendKeyV2 = FriendKeyV2(friendKeyProxy);
//         friendKeyV2.initializeV2();
//         vm.stopPrank();

//         // Test that old functions still work
//         uint256 newPrice = friendKeyV2.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 5);
//         assertGt(newPrice, 0, "Price calculation should still work");

//         // Buy more shares after upgrade
//         vm.startPrank(buyerAccount);
//         mockUsdc.approve(address(friendKeyV2), newPrice);
//         friendKeyV2.buyShares(CREATOR_TOKEN_ID, 5, 0);
//         vm.stopPrank();

//         assertEq(friendKeyV2.totalSupply(CREATOR_TOKEN_ID), 11, "Should be able to buy after upgrade");
//     }

//     function testFriendKeyUpgrade_CustomFeeMultiplier() public {
//         // Get base price before upgrade
//         uint256 basePriceBeforeUpgrade = friendKeyV1.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 10);

//         // Upgrade to V2
//         vm.startPrank(owner);
//         address friendKeyProxy = address(friendKeyV1);
//         Upgrades.upgradeProxy(friendKeyProxy, "FriendKeyV2.sol", "");
//         friendKeyV2 = FriendKeyV2(friendKeyProxy);
//         friendKeyV2.initializeV2();
//         vm.stopPrank();

//         // Verify price is same before multiplier is set
//         uint256 priceAfterUpgrade = friendKeyV2.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 10);
//         assertEq(priceAfterUpgrade, basePriceBeforeUpgrade, "Price should be same after upgrade before multiplier");
//     }

//     // ============================================
//     // FRIENDROOMMANAGER UPGRADE TESTS
//     // ============================================

//     function testRoomManagerUpgrade_PreservesStorage() public {
//         // Record V1 state
//         uint16 v1DevFee = roomManagerV1.devFeePercent();
//         uint16 v1CreatorFee = roomManagerV1.creatorFeePercent();
//         address v1FriendKey = address(roomManagerV1.friendKey());
//         address v1DevDest = roomManagerV1.devFeeDestination();
//         address v1PoolDest = roomManagerV1.tradingPoolFeeDestination();

//         // Set some limits
//         vm.prank(owner);
//         roomManagerV1.setMaxRoomsPerTier(IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Club, 3);

//         // Upgrade to V2
//         vm.startPrank(owner);
//         address roomManagerProxy = address(roomManagerV1);
//         Upgrades.upgradeProxy(roomManagerProxy, "FriendRoomManagerV2.sol", "");
//         roomManagerV2 = FriendRoomManagerV2(roomManagerProxy);
//         roomManagerV2.initializeV2();
//         vm.stopPrank();

//         // Verify storage is preserved
//         assertEq(roomManagerV2.devFeePercent(), v1DevFee, "Dev fee should be preserved");
//         assertEq(roomManagerV2.creatorFeePercent(), v1CreatorFee, "Creator fee should be preserved");
//         assertEq(address(roomManagerV2.friendKey()), v1FriendKey, "FriendKey should be preserved");
//         assertEq(roomManagerV2.devFeeDestination(), v1DevDest, "Dev destination should be preserved");
//         assertEq(roomManagerV2.tradingPoolFeeDestination(), v1PoolDest, "Pool destination should be preserved");

//         // Verify limits are preserved
//         assertEq(
//             roomManagerV2.maxRoomsPerTier(IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Club),
//             3,
//             "Room limits should be preserved"
//         );
//     }

//     function testRoomManagerUpgrade_NewV2Features() public {
//         // Upgrade to V2
//         vm.startPrank(owner);
//         address roomManagerProxy = address(roomManagerV1);
//         Upgrades.upgradeProxy(roomManagerProxy, "FriendRoomManagerV2.sol", "");
//         roomManagerV2 = FriendRoomManagerV2(roomManagerProxy);
//         roomManagerV2.initializeV2();
//         vm.stopPrank();

//         // Test V2 features
//         assertTrue(roomManagerV2.v2FeatureEnabled(), "V2 features should be enabled");

//         // Test setting room creation fee
//         vm.prank(owner);
//         roomManagerV2.setRoomCreationFee(IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Club, 100); // 1%
//         assertEq(
//             roomManagerV2.getRoomCreationFee(IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Club),
//             100,
//             "Creation fee should be set"
//         );

//         // Test setting minimum stake
//         vm.prank(owner);
//         roomManagerV2.setMinimumStakeRequired(IFriendKey.RoomType.Trading, 1000 * (10 ** 6));
//         assertEq(
//             roomManagerV2.minimumStakeRequired(IFriendKey.RoomType.Trading),
//             1000 * (10 ** 6),
//             "Minimum stake should be set"
//         );
//     }

//     function testRoomManagerUpgrade_BackwardCompatibility() public {
//         // Use V1 features
//         (uint16 devFee, uint16 creatorFee, uint16 poolFee) = roomManagerV1.getTradingFees();
//         assertGt(devFee, 0, "Should have dev fee");
//         assertGt(creatorFee, 0, "Should have creator fee");

//         // Upgrade to V2
//         vm.startPrank(owner);
//         address roomManagerProxy = address(roomManagerV1);
//         Upgrades.upgradeProxy(roomManagerProxy, "FriendRoomManagerV2.sol", "");
//         roomManagerV2 = FriendRoomManagerV2(roomManagerProxy);
//         roomManagerV2.initializeV2();
//         vm.stopPrank();

//         // Test that old functions still work
//         (uint16 devFeeV2, uint16 creatorFeeV2, uint16 poolFeeV2) = roomManagerV2.getTradingFees();
//         assertEq(devFeeV2, devFee, "Dev fee should be preserved");
//         assertEq(creatorFeeV2, creatorFee, "Creator fee should be preserved");
//         assertEq(poolFeeV2, poolFee, "Pool fee should be preserved");

//         // Test that FriendKey can still call RoomManager functions
//         // Use a different account that hasn't registered yet
//         address newCreator = vm.addr(100);
//         bool canRegister = friendKeyV1.canRegisterRoom(newCreator, FriendKey.RoomType.Trading, FriendKey.RoomTier.Club);
//         assertTrue(canRegister, "Should still be able to check room registration");

//         // Verify the creator who already registered can't register again (limit is 1)
//         bool existingCreatorCanRegister =
//             friendKeyV1.canRegisterRoom(creatorAccount, FriendKey.RoomType.Trading, FriendKey.RoomTier.Club);
//         assertFalse(existingCreatorCanRegister, "Creator who already registered should not be able to register again");
//     }

//     function testRoomManagerUpgrade_FeeCollection() public {
//         // Upgrade to V2
//         vm.startPrank(owner);
//         address roomManagerProxy = address(roomManagerV1);
//         Upgrades.upgradeProxy(roomManagerProxy, "FriendRoomManagerV2.sol", "");
//         roomManagerV2 = FriendRoomManagerV2(roomManagerProxy);
//         roomManagerV2.initializeV2();

//         // Set creation fee
//         roomManagerV2.setRoomCreationFee(IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Exclusive, 200); // 2%
//         vm.stopPrank();

//         // Register a new creator (this should trigger fee collection)
//         address newCreator = vm.addr(100);
//         mockUsdc.mint(newCreator, 1_000_000 * (10 ** 6));

//         vm.startPrank(newCreator);
//         string memory metadata = "";
//         bytes memory signature = _getRegisterCreatorSignature(newCreator, FriendKey.RoomTier.Exclusive, 0, metadata);
//         friendKeyV1.registerCreator(FriendKey.RoomTier.Exclusive, 0, metadata, signature);
//         vm.stopPrank();

//         // Check that fee was tracked
//         uint256 totalFees =
//             roomManagerV2.getTotalFeesCollected(IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Exclusive);
//         assertEq(totalFees, 200, "Fee should be tracked");
//     }

//     // ============================================
//     // INTEGRATION TESTS
//     // ============================================

//     function testFullUpgrade_Integration() public {
//         // Initial state: Buy shares in V1
//         vm.startPrank(buyerAccount);
//         uint256 price = friendKeyV1.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 20);
//         mockUsdc.approve(address(friendKeyV1), price);
//         friendKeyV1.buyShares(CREATOR_TOKEN_ID, 20, 0);
//         vm.stopPrank();

//         uint256 v1Balance = friendKeyV1.balanceOf(buyerAccount, CREATOR_TOKEN_ID);
//         friendKeyV1.creatorByTokenId(CREATOR_TOKEN_ID);

//         // Upgrade both contracts
//         vm.startPrank(owner);
//         // Upgrade RoomManager first
//         address roomManagerProxy = address(roomManagerV1);
//         Upgrades.upgradeProxy(roomManagerProxy, "FriendRoomManagerV2.sol", "");
//         roomManagerV2 = FriendRoomManagerV2(roomManagerProxy);
//         roomManagerV2.initializeV2();

//         // Upgrade FriendKey
//         address friendKeyProxy = address(friendKeyV1);
//         Upgrades.upgradeProxy(friendKeyProxy, "FriendKeyV2.sol", "");
//         friendKeyV2 = FriendKeyV2(friendKeyProxy);
//         friendKeyV2.initializeV2();
//         vm.stopPrank();

//         // Verify balances are preserved
//         assertEq(friendKeyV2.balanceOf(buyerAccount, CREATOR_TOKEN_ID), v1Balance, "Balance should be preserved");

//         // Test that buying still works
//         vm.startPrank(buyerAccount);
//         uint256 newPrice = friendKeyV2.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 10);
//         mockUsdc.approve(address(friendKeyV2), newPrice);
//         friendKeyV2.buyShares(CREATOR_TOKEN_ID, 10, 0);
//         vm.stopPrank();

//         assertEq(friendKeyV2.balanceOf(buyerAccount, CREATOR_TOKEN_ID), v1Balance + 10, "Should be able to buy");

//         // Test V2 features work together
//         vm.prank(owner);
//     }

//     function testVersionInfo() public {
//         // Upgrade to V2
//         vm.startPrank(owner);
//         address friendKeyProxy = address(friendKeyV1);
//         Upgrades.upgradeProxy(friendKeyProxy, "FriendKeyV2.sol", "");
//         friendKeyV2 = FriendKeyV2(friendKeyProxy);
//         friendKeyV2.initializeV2();

//         address roomManagerProxy = address(roomManagerV1);
//         Upgrades.upgradeProxy(roomManagerProxy, "FriendRoomManagerV2.sol", "");
//         roomManagerV2 = FriendRoomManagerV2(roomManagerProxy);
//         roomManagerV2.initializeV2();
//         vm.stopPrank();

//         assertEq(friendKeyV2.version(), "2.0.0", "FriendKey should report V2");
//         assertEq(roomManagerV2.version(), "2.0.0", "RoomManager should report V2");
//     }
// }
