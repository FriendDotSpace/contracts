// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IFriendKey is IERC1155 {
    enum RoomTier {
        Casual,
        Club,
        Exclusive
    }
    enum RoomType {
        Trading,
        Social
    }

    function BPS_SCALE() external view returns (uint256);
    function devFeeDestination() external view returns (address);
    function devPerformanceFeePercent() external view returns (uint256);
    function creatorPerformanceFeePercent() external view returns (uint256);
    function bondingToken() external view returns (address);

    function registerCreator(RoomTier tier, uint256 additionalKeys, string calldata metadata, bytes calldata signature)
        external
        returns (uint256);
    function registerCreator(string calldata metadata, bytes calldata signature) external returns (uint256);
    function registerSocialCreator(
        RoomTier tier,
        uint256 additionalKeys,
        string calldata metadata,
        bytes calldata signature
    ) external returns (uint256);
    function registerSocialCreator(string calldata metadata, bytes calldata signature) external returns (uint256);
    function creatorByTokenId(uint256 tokenId) external view returns (address);
    function roomTiers(uint256 tokenId) external view returns (RoomTier);
    function roomTypes(uint256 tokenId) external view returns (RoomType);
    function canRegisterRoom(address creator, RoomType roomType, RoomTier tier) external view returns (bool);

    // Fee management functions
    function getPerformanceFees() external view returns (uint16 dev, uint16 creator);
    function getFeeDestinations() external view returns (address dev, address pool);
}
