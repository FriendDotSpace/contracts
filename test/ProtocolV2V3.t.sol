// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendPoolV3} from "src/FriendPoolV3.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";
import {FriendRoomManagerV2} from "src/FriendRoomManagerV2.sol";
import {FriendStake} from "src/FriendStake.sol";
import {IFriendKey} from "src/interfaces/IFriendKey.sol";
import {MockERC20, DlnSourceMock} from "./FriendPool.t.sol";

/// @notice Regression coverage for implementations shaped like production upgrades (V2/V3 lines).
contract ProtocolV2V3Test is Test {
    FriendKey public friendKey;
    FriendPoolV3 public friendPool;
    FriendRoomManager public roomManager;
    MockERC20 public mockUsdc;
    DlnSourceMock public dlnSourceMock;

    address public owner;
    address public buyer;
    uint256 public constant CREATOR_TOKEN_ID = 1;

    uint256 private constant OWNER_PRIVATE_KEY = 1;
    bytes32 private constant REGISTER_CREATOR_TYPEHASH = keccak256(
        "RegisterCreator(address account,uint8 roomType,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)"
    );
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256(bytes("FriendKey"));
    bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(friendKey)));
    }

    function _registerTradingCreator(address creator) internal {
        string memory metadata = "v3_pool_test";
        uint256 nonce = friendKey.registerCreatorNonces(creator);
        bytes32 metadataHash = keccak256(bytes(metadata));
        bytes32 structHash = keccak256(
            abi.encode(
                REGISTER_CREATOR_TYPEHASH,
                creator,
                uint8(FriendKey.RoomType.Trading),
                uint8(FriendKey.RoomTier.Club),
                uint256(0),
                nonce,
                metadataHash
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(creator);
        friendKey.registerCreator(metadata, signature);
        vm.stopPrank();
    }

    /// @dev Skips OZ upgrades-core CLI validation so `forge test` works after incremental compiles (CI still runs full `forge build`).
    function _unsafeOpts() internal pure returns (Options memory o) {
        o.unsafeSkipAllChecks = true;
    }

    function _deployStack(address friendStakeBeacon) internal {
        Options memory opts = _unsafeOpts();
        owner = vm.addr(1);
        buyer = vm.addr(6);
        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
        dlnSourceMock = new DlnSourceMock();

        vm.startPrank(owner);
        bytes memory roomManagerInitData = abi.encodeCall(FriendRoomManager.initialize, (owner));
        address roomManagerProxy = Upgrades.deployUUPSProxy("FriendRoomManager.sol", roomManagerInitData, opts);
        roomManager = FriendRoomManager(roomManagerProxy);

        bytes memory friendKeyInit =
            abi.encodeCall(FriendKey.initialize, (owner, address(mockUsdc), friendStakeBeacon, address(roomManager)));
        friendKey = FriendKey(Upgrades.deployUUPSProxy("FriendKey.sol", friendKeyInit, opts));
        roomManager.setFriendKey(address(friendKey));

        bytes memory poolInit =
            abi.encodeCall(FriendPoolV3.initialize, (owner, address(friendKey), address(dlnSourceMock)));
        friendPool = FriendPoolV3(Upgrades.deployUUPSProxy("FriendPoolV3.sol", poolInit, opts));
        roomManager.setFeeDestinations(owner, address(friendPool));
        vm.stopPrank();

        address creator = vm.addr(5);
        vm.deal(creator, 1 ether);
        _registerTradingCreator(creator);
        mockUsdc.mint(buyer, 1_000_000 * (10 ** 6));
    }

    function testFriendPoolV3_transferFundsPartialyToRoom() public {
        Options memory opts = _unsafeOpts();
        address beaconOwner = vm.addr(1);
        address beacon = Upgrades.deployBeacon("FriendStake.sol", beaconOwner, opts);
        _deployStack(beacon);

        vm.startPrank(buyer);
        uint256 cost = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 5);
        mockUsdc.approve(address(friendKey), cost);
        friendKey.buyShares(CREATOR_TOKEN_ID, 5, type(uint256).max);
        vm.stopPrank();

        uint256 reserves = friendPool.poolReserves(CREATOR_TOKEN_ID);
        assertGt(reserves, 0);

        uint256 amount = reserves / 2;
        uint256 topupFee = amount / 10;
        assertGt(amount, topupFee);

        (address devDest,) = friendKey.getFeeDestinations();
        uint256 devBefore = mockUsdc.balanceOf(devDest);
        uint256 buyerBefore = mockUsdc.balanceOf(buyer);
        uint256 poolBefore = mockUsdc.balanceOf(address(friendPool));

        vm.prank(owner);
        friendPool.transferFundsPartialyToRoom(CREATOR_TOKEN_ID, amount, topupFee, buyer);

        assertEq(mockUsdc.balanceOf(devDest), devBefore + topupFee);
        assertEq(mockUsdc.balanceOf(buyer), buyerBefore + (amount - topupFee));
        assertEq(mockUsdc.balanceOf(address(friendPool)), poolBefore - amount);
        assertEq(friendPool.poolReserves(CREATOR_TOKEN_ID), reserves - amount);
    }

    function testFriendRoomManagerV2_upgradeAndMaxRoomsPerType() public {
        Options memory opts = _unsafeOpts();
        address beaconOwner = vm.addr(1);
        address beacon = Upgrades.deployBeacon("FriendStake.sol", beaconOwner, opts);
        _deployStack(beacon);

        Upgrades.upgradeProxy(address(roomManager), "FriendRoomManagerV2.sol", "", opts, owner);

        FriendRoomManagerV2 rm = FriendRoomManagerV2(address(roomManager));
        vm.startPrank(owner);
        rm.setMaxRoomsPerType(IFriendKey.RoomType.Social, 3);
        vm.stopPrank();
        assertEq(rm.maxRoomsPerType(IFriendKey.RoomType.Social), 3);
    }

    function testFriendStakeV3_beaconDefaultBridgeFee() public {
        Options memory opts = _unsafeOpts();
        address beaconOwner = vm.addr(1);
        address beacon = Upgrades.deployBeacon("FriendStakeV3.sol", beaconOwner, opts);
        _deployStack(beacon);

        FriendStake stake = FriendStake(friendKey.stakingPoolByTokenId(CREATOR_TOKEN_ID));
        assertEq(stake.bridgeFee(), 100000);
    }
}
