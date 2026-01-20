// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IFriendKey} from "./interfaces/IFriendKey.sol";
import {Errors} from "./libraries/Errors.sol";
import {FriendRoomManager} from "./FriendRoomManager.sol";

/**
 * @title FriendRoomManagerV2
 * @notice Extension contract to manage room creation limits and advanced room features
 * @custom:oz-upgrades-from FriendRoomManager
 * @dev This contract works alongside FriendKey to provide room management and some admin
 *      functionality for the FriendKey contract.
 *      V2 adds support for total room limits per room type (across all tiers).
 */
contract FriendRoomManagerV2 is FriendRoomManager {
    // ============================================
    // NEW STATE VARIABLES (V2)
    // ============================================

    /// @notice Maximum number of rooms allowed per creator per room type (across all tiers)
    /// @dev If set to 0, only per-tier limits apply. If > 0, this is the total limit across all tiers.
    mapping(IFriendKey.RoomType => uint256) public maxRoomsPerType;

    /// @notice Total room count per creator per room type (across all tiers)
    /// @dev since we are gonna upgrade this, old users who have trading rooms will have 0 still,but that's fine as of now beacuse trading rooms have
    /// the limit set tier based already 1 per tier (for club.exclusive), so this is mainly for social rooms which are 0 as of now in prod/staging
    mapping(address => mapping(IFriendKey.RoomType => uint256)) public creatorTotalRoomCount;

    /// @dev Storage gap for future upgrades (reduced by 2 slots for new mappings)
    uint256[45] private __gap;

    // ============================================
    // NEW EVENTS (V2)
    // ============================================

    event MaxRoomsPerTypeChanged(IFriendKey.RoomType indexed roomType, uint256 maxRooms);

    // ============================================
    // NEW FUNCTIONS (V2)
    // ============================================

    /**
     * @notice Owner function to set maximum rooms per room type (across all tiers)
     * @dev Setting to 0 disables this limit (only per-tier limits apply)
     *      Setting to > 0 enforces a total limit across all tiers for this room type
     *      Example: Set to 1 for Social rooms to allow only 1 social room total (any tier)
     * @param roomType Type of room
     * @param maxRooms Maximum total number of rooms allowed across all tiers
     */
    function setMaxRoomsPerType(IFriendKey.RoomType roomType, uint256 maxRooms) external onlyOwner {
        maxRoomsPerType[roomType] = maxRooms;
        emit MaxRoomsPerTypeChanged(roomType, maxRooms);
    }

    /**
     * @notice Gets the total number of rooms a creator has for a specific room type (across all tiers)
     * @param creator Address of the creator
     * @param roomType Type of room
     * @return Total number of rooms created across all tiers
     */
    function getCreatorTotalRoomCount(address creator, IFriendKey.RoomType roomType) public view returns (uint256) {
        return creatorTotalRoomCount[creator][roomType];
    }

    // ============================================
    // OVERRIDDEN FUNCTIONS (V2)
    // ============================================

    /**
     * @notice Checks if a creator can register another room of a specific type/tier
     * @dev V2: Now checks both per-tier limit AND total per-room-type limit
     * @param creator Address of the creator
     * @param roomType Type of room
     * @param tier Tier of room
     * @return True if creator can register, false otherwise
     */
    function canRegisterRoom(address creator, IFriendKey.RoomType roomType, IFriendKey.RoomTier tier)
        public
        view
        virtual
        override
        returns (bool)
    {
        // Check per-tier limit
        uint256 maxAllowedPerTier = maxRoomsPerTier[roomType][tier];
        if (creatorRoomNonce[creator][roomType][tier] >= maxAllowedPerTier) {
            return false;
        }

        // Check total per-room-type limit (if configured)
        uint256 maxAllowedPerType = maxRoomsPerType[roomType];
        if (maxAllowedPerType > 0) {
            uint256 currentTotal = creatorTotalRoomCount[creator][roomType];
            if (currentTotal >= maxAllowedPerType) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Updates room tracking when a new room is registered
     * @dev V2: Now also increments the total room count per room type
     * @param creator Address of the creator
     * @param roomType Type of room
     * @param tier Tier of room
     * @param tokenId ID of the token being created
     */
    function _updateRoomTracking(
        address creator,
        IFriendKey.RoomType roomType,
        IFriendKey.RoomTier tier,
        uint256 tokenId
    ) internal virtual override {
        super._updateRoomTracking(creator, roomType, tier, tokenId);
        creatorTotalRoomCount[creator][roomType]++;
    }
}
