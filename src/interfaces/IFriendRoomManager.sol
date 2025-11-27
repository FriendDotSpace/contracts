// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IFriendKey} from "./IFriendKey.sol";

interface IFriendRoomManager {
    // Room management functions
    function checkAndUpdateRoomRegistration(
        address creator,
        IFriendKey.RoomType roomType,
        IFriendKey.RoomTier tier,
        uint256 tokenId
    ) external;

    function canRegisterRoom(address creator, IFriendKey.RoomType roomType, IFriendKey.RoomTier tier)
        external
        view
        returns (bool);

    function getCreatorRoomCount(address creator, IFriendKey.RoomType roomType, IFriendKey.RoomTier tier)
        external
        view
        returns (uint256);

    function setFriendKey(address _friendKey) external;

    // Room type management functions
    function setMaxRoomsPerTier(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier, uint256 maxRooms) external;
    function enableRoomType(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier) external;
    function disableRoomType(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier) external;

    // Fee management functions (moved from FriendKey for size optimization)
    function setFeeDestinations(address _devDest, address _poolDest) external;
    function setTradingFees(uint16 _devFee, uint16 _creatorFee, uint16 _poolFee) external;
    function setPerformanceFees(uint16 _devFee, uint16 _creatorFee) external;
    function setSocialFees(uint16 _devFee, uint16 _creatorFee) external;

    // Fee getter functions (for FriendKey to fetch fees)
    function getTradingFees() external view returns (uint16 dev, uint16 creator, uint16 pool);
    function getPerformanceFees() external view returns (uint16 dev, uint16 creator);
    function getSocialFees() external view returns (uint16 dev, uint16 creator);
    function getFeeDestinations() external view returns (address dev, address pool);

    // Bonding curve config
    function getDivisor(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier) external view returns (uint256);
    function setBondingCurveDivisors(uint256[3] calldata _divisors) external;
    function setSocialDivisors(uint256[3] calldata _divisors) external;
    function setEligibilityDuration(uint256 _duration) external;
    function eligibilityDuration() external view returns (uint256);
    function authority() external view returns (address);
    function setAuthority(address _authority) external;
}
