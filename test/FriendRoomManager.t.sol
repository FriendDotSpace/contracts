// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {FriendRoomManager} from "../src/FriendRoomManager.sol";
import {IFriendKey} from "../src/interfaces/IFriendKey.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract MockFriendKey {
    uint256 private _nextTokenId;

    function registerCreator(
        IFriendKey.RoomTier,
        /* tier */
        uint256,
        /* additionalKeys */
        string calldata,
        /* metadata */
        bytes calldata /* signature */
    )
        external
        returns (uint256)
    {
        return ++_nextTokenId;
    }

    function creatorByTokenId(uint256 tokenId) external pure returns (address) {
        // casting to 'uint160' is safe because tokenId is used as a mock creator address
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(tokenId));
    }

    function roomTiers(uint256) external pure returns (IFriendKey.RoomTier) {
        return IFriendKey.RoomTier.Club;
    }

    function roomTypes(uint256) external pure returns (IFriendKey.RoomType) {
        return IFriendKey.RoomType.Trading;
    }

    function canRegisterRoom(address, IFriendKey.RoomType, IFriendKey.RoomTier) external pure returns (bool) {
        return true;
    }

    // IERC1155 functions (minimal implementation)
    function balanceOf(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function balanceOfBatch(address[] calldata, uint256[] calldata) external pure returns (uint256[] memory) {
        return new uint256[](0);
    }
    function setApprovalForAll(address, bool) external {}

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }
    function safeTransferFrom(address, address, uint256, uint256, bytes calldata) external {}
    function safeBatchTransferFrom(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external {}

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract FriendRoomManagerTest is Test {
    FriendRoomManager public roomManager;
    MockFriendKey public mockFriendKey;
    address public owner;
    address public creator;

    function setUp() public {
        owner = address(this);
        creator = vm.addr(1);

        // Deploy mock FriendKey
        mockFriendKey = new MockFriendKey();

        // Deploy RoomManager
        bytes memory initData = abi.encodeCall(FriendRoomManager.initialize, (owner));

        address roomManagerProxy = Upgrades.deployUUPSProxy("FriendRoomManager.sol", initData);

        roomManager = FriendRoomManager(roomManagerProxy);
        roomManager.setFriendKey(address(mockFriendKey));
    }

    function testInitialLimits() public view {
        // Trading rooms: 1 per tier (Casual disabled by default)
        assertEq(roomManager.maxRoomsPerTier(IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Casual), 0);
        assertEq(roomManager.maxRoomsPerTier(IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Club), 1);
        assertEq(roomManager.maxRoomsPerTier(IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Exclusive), 1);

        // Social rooms: All disabled by default
        assertEq(roomManager.maxRoomsPerTier(IFriendKey.RoomType.Social, IFriendKey.RoomTier.Casual), 0);
        assertEq(roomManager.maxRoomsPerTier(IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club), 0);
        assertEq(roomManager.maxRoomsPerTier(IFriendKey.RoomType.Social, IFriendKey.RoomTier.Exclusive), 0);
    }

    function testCanRegisterRoom() public view {
        // Creator should be able to register first trading room (Club and Exclusive enabled)
        assertTrue(roomManager.canRegisterRoom(creator, IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Club));
        assertTrue(roomManager.canRegisterRoom(creator, IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Exclusive));

        // Social rooms should NOT be registerable (disabled by default)
        assertFalse(roomManager.canRegisterRoom(creator, IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club));
        assertFalse(roomManager.canRegisterRoom(creator, IFriendKey.RoomType.Social, IFriendKey.RoomTier.Casual));
    }

    function testCheckAndUpdateRoomRegistration() public {
        vm.startPrank(address(mockFriendKey));

        // Simulate FriendKey calling the room manager
        roomManager.checkAndUpdateRoomRegistration(creator, IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Club, 1);

        assertEq(roomManager.getCreatorRoomCount(creator, IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Club), 1);

        vm.stopPrank();
    }

    function testRoomLimitEnforcement() public {
        vm.startPrank(address(mockFriendKey));

        // Register first trading room (should succeed)
        roomManager.checkAndUpdateRoomRegistration(creator, IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Club, 1);

        // Try to register second trading room (should fail)
        vm.expectRevert();
        roomManager.checkAndUpdateRoomRegistration(creator, IFriendKey.RoomType.Trading, IFriendKey.RoomTier.Club, 2);

        vm.stopPrank();
    }

    function testSocialRoomMultipleRegistrations() public {
        // First, enable social rooms with limit of 5
        roomManager.setMaxRoomsPerTier(IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club, 5);

        vm.startPrank(address(mockFriendKey));

        // Register multiple social rooms (should succeed up to limit)
        for (uint256 i = 0; i < 5; i++) {
            roomManager.checkAndUpdateRoomRegistration(
                creator, IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club, i + 1
            );
        }

        assertEq(roomManager.getCreatorRoomCount(creator, IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club), 5);

        // Try to register 6th social room (should fail)
        vm.expectRevert();
        roomManager.checkAndUpdateRoomRegistration(creator, IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club, 6);

        vm.stopPrank();
    }

    function testSetMaxRoomsPerTier() public {
        // Increase social room limit
        roomManager.setMaxRoomsPerTier(IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club, 10);

        assertEq(roomManager.maxRoomsPerTier(IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club), 10);
    }

    function testGetCreatorRooms() public {
        // First, enable social rooms with limit of 5
        roomManager.setMaxRoomsPerTier(IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club, 5);

        vm.startPrank(address(mockFriendKey));

        // Register a few rooms
        roomManager.checkAndUpdateRoomRegistration(creator, IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club, 1);
        roomManager.checkAndUpdateRoomRegistration(creator, IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club, 2);

        uint256[] memory rooms =
            roomManager.getCreatorRooms(creator, IFriendKey.RoomType.Social, IFriendKey.RoomTier.Club);

        assertEq(rooms.length, 2);
        assertEq(rooms[0], 1);
        assertEq(rooms[1], 2);

        vm.stopPrank();
    }
}
