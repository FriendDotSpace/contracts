// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IFriendKey} from "./interfaces/IFriendKey.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title FriendRoomManager
 * @notice Extension contract to manage room creation limits and advanced room features
 * @dev This contract works alongside FriendKey to provide enhanced room management
 */
contract FriendRoomManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Use enums from IFriendKey interface

    /// @notice Reference to the main FriendKey contract
    IFriendKey public friendKey;

    // ============ FEE STORAGE (Moved from FriendKey for size optimization) ============

    /// @notice Packed fee percentages (in basis points) for trading rooms
    uint16 public devFeePercent;
    uint16 public creatorFeePercent;
    uint16 public tradingPoolFeePercent;
    uint16 public devPerformanceFeePercent;
    uint16 public creatorPerformanceFeePercent;

    // Fee storage moved to RoomManager
    /// @notice Address of the FriendStake beacon contract for beacon proxy cloning
    address public friendStakeBeacon;

    /// @notice Fee percentages for social rooms
    uint16 public socialDevFeePercent;
    uint16 public socialCreatorFeePercent;

    /// @notice Fee destination addresses
    address public devFeeDestination;
    address public tradingPoolFeeDestination;

    /// @notice Bonding curve divisors for different room tiers [Casual, Club, Elite]
    uint256[3] public bondingCurveDivisors;
    /// @notice Social room divisors (different pricing for social rooms)
    uint256[3] public socialDivisors;
    /// @notice Authority address for signature verification
    address public authority;
    /// @notice Duration that a stake must be held to be eligible for rewards
    uint256 public eligibilityDuration;

    /// @notice Maximum number of rooms allowed per creator per tier per room type
    mapping(IFriendKey.RoomType => mapping(IFriendKey.RoomTier => uint256)) public maxRoomsPerTier;

    /// @notice Nonce tracking for room creation per creator per room type per tier
    mapping(address => mapping(IFriendKey.RoomType => mapping(IFriendKey.RoomTier => uint256))) public creatorRoomNonce;

    /// @notice Track all room IDs created by a creator for a specific type/tier
    mapping(address => mapping(IFriendKey.RoomType => mapping(IFriendKey.RoomTier => uint256[]))) public
        creatorRoomsByTier;

    /// @dev Storage gap for future upgrades
    uint256[47] private __gap;

    event MaxRoomsPerTierChanged(
        IFriendKey.RoomType indexed roomType, IFriendKey.RoomTier indexed tier, uint256 maxRooms
    );
    event RoomRegistered(
        address indexed creator, IFriendKey.RoomType indexed roomType, IFriendKey.RoomTier indexed tier, uint256 tokenId
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        // Set default limits and fees
        _setDefaultLimits();
        _setDefaultFees();
    }

    /**
     * @notice Sets the FriendKey contract address
     * @dev Only callable by owner, typically called during FriendKey initialization
     */
    function setFriendKey(address _friendKey) external onlyOwner {
        if (_friendKey == address(0)) revert Errors.ZeroAddress();
        friendKey = IFriendKey(_friendKey);
    }

    // ============ FEE MANAGEMENT (Moved from FriendKey for size optimization) ============

    /**
     * @notice Sets fee destinations for both dev and trading pool
     * @dev Storage moved from FriendKey to reduce contract size
     */
    function setFeeDestinations(address _devDest, address _poolDest) external onlyOwner {
        if (_devDest == address(0)) revert Errors.ZeroAddress();
        if (_poolDest == address(0)) revert Errors.ZeroAddress();

        devFeeDestination = _devDest;
        tradingPoolFeeDestination = _poolDest;
    }

    /**
     * @notice Sets trading room fees (dev, creator, trading pool)
     * @dev Storage moved from FriendKey to reduce contract size
     */
    function setTradingFees(uint16 _devFee, uint16 _creatorFee, uint16 _poolFee) external onlyOwner {
        uint256 BPS_SCALE = 10000;
        if (_devFee + _creatorFee + _poolFee > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();

        devFeePercent = _devFee;
        creatorFeePercent = _creatorFee;
        tradingPoolFeePercent = _poolFee;
    }

    /**
     * @notice Sets performance fees (dev, creator)
     * @dev Storage moved from FriendKey to reduce contract size
     */
    function setPerformanceFees(uint16 _devFee, uint16 _creatorFee) external onlyOwner {
        devPerformanceFeePercent = _devFee;
        creatorPerformanceFeePercent = _creatorFee;
    }

    /**
     * @notice Sets social room fees (dev, creator)
     * @dev Storage moved from FriendKey to reduce contract size
     */
    function setSocialFees(uint16 _devFee, uint16 _creatorFee) external onlyOwner {
        uint256 BPS_SCALE = 10000;
        if (_devFee + _creatorFee > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();

        socialDevFeePercent = _devFee;
        socialCreatorFeePercent = _creatorFee;
    }

    function setRoomManagerInFriendKey(address _roomManager) external onlyOwner {
        (bool success,) = address(friendKey).call(abi.encodeWithSignature("_setRoomManager(address)", _roomManager));
        require(success, "Failed to set room manager");
    }

    // ============ FEE GETTER FUNCTIONS ============

    /**
     * @notice Gets trading fees for a specific room type
     * @dev Used by FriendKey to fetch fees
     */
    function getTradingFees() external view returns (uint16 dev, uint16 creator, uint16 pool) {
        return (devFeePercent, creatorFeePercent, tradingPoolFeePercent);
    }

    /**
     * @notice Gets performance fees
     * @dev Used by FriendKey to fetch fees
     */
    function getPerformanceFees() external view returns (uint16 dev, uint16 creator) {
        return (devPerformanceFeePercent, creatorPerformanceFeePercent);
    }

    /**
     * @notice Gets social fees
     * @dev Used by FriendKey to fetch fees
     */
    function getSocialFees() external view returns (uint16 dev, uint16 creator) {
        return (socialDevFeePercent, socialCreatorFeePercent);
    }

    /**
     * @notice Gets fee destinations
     * @dev Used by FriendKey to fetch destinations
     */
    function getFeeDestinations() external view returns (address dev, address pool) {
        return (devFeeDestination, tradingPoolFeeDestination);
    }

    // ============ BONDING CURVE CONFIG FUNCTIONS ============

    function getDivisor(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier) external view returns (uint256) {
        if (roomType == IFriendKey.RoomType.Social) {
            return socialDivisors[uint256(tier)];
        }
        return bondingCurveDivisors[uint256(tier)];
    }

    function setBondingCurveDivisors(uint256[3] calldata _divisors) external onlyOwner {
        bondingCurveDivisors = _divisors;
    }

    function setSocialDivisors(uint256[3] calldata _divisors) external onlyOwner {
        socialDivisors = _divisors;
    }

    function setAuthority(address _authority) external onlyOwner {
        if (_authority == address(0)) revert Errors.ZeroAddress();
        authority = _authority;
    }

    function setEligibilityDuration(uint256 _duration) external onlyOwner {
        eligibilityDuration = _duration;
    }

    function _setDefaultLimits() internal {
        // Trading rooms: All tiers enabled for testing
        maxRoomsPerTier[IFriendKey.RoomType.Trading][IFriendKey.RoomTier.Casual] = 1;
        maxRoomsPerTier[IFriendKey.RoomType.Trading][IFriendKey.RoomTier.Club] = 1;
        maxRoomsPerTier[IFriendKey.RoomType.Trading][IFriendKey.RoomTier.Exclusive] = 1;

        // Social rooms: Multiple allowed per tier for testing
        maxRoomsPerTier[IFriendKey.RoomType.Social][IFriendKey.RoomTier.Casual] = 5;
        maxRoomsPerTier[IFriendKey.RoomType.Social][IFriendKey.RoomTier.Club] = 5;
        maxRoomsPerTier[IFriendKey.RoomType.Social][IFriendKey.RoomTier.Exclusive] = 5;
    }

    function _setDefaultFees() internal {
        // Default trading fees (in basis points)
        devFeePercent = 250; // 2.5%
        creatorFeePercent = 250; // 2.5%
        tradingPoolFeePercent = 250; // 2.5%

        // Default performance fees
        devPerformanceFeePercent = 500; // 5%
        creatorPerformanceFeePercent = 500; // 5%

        // Default social fees (lower than trading)
        socialDevFeePercent = 125; // 1.25%
        socialCreatorFeePercent = 250; // 2.5%

        // Set default bonding curve divisors
        bondingCurveDivisors = [4000, 40, 4]; // [Casual, Club, Elite]
        socialDivisors = [8000, 80, 8]; // Higher divisors for social rooms (lower prices)
        eligibilityDuration = 24 hours;
    }

    /**
     * @notice Checks if a creator can register a room and updates tracking
     * @dev Called by FriendKey before registration
     */
    function checkAndUpdateRoomRegistration(
        address creator,
        IFriendKey.RoomType roomType,
        IFriendKey.RoomTier tier,
        uint256 tokenId
    ) external {
        // Only FriendKey can call this
        require(msg.sender == address(friendKey), Errors.NotFriendKey());

        // Check if creator can register this room type/tier
        if (!canRegisterRoom(creator, roomType, tier)) {
            revert Errors.RoomLimitExceeded();
        }

        // Update our tracking
        _updateRoomTracking(creator, roomType, tier, tokenId);

        emit RoomRegistered(creator, roomType, tier, tokenId);
    }

    function _updateRoomTracking(
        address creator,
        IFriendKey.RoomType roomType,
        IFriendKey.RoomTier tier,
        uint256 tokenId
    ) internal {
        creatorRoomNonce[creator][roomType][tier]++;
        creatorRoomsByTier[creator][roomType][tier].push(tokenId);
    }

    /**
     * @notice Checks if a creator can register another room of a specific type/tier
     */
    function canRegisterRoom(address creator, IFriendKey.RoomType roomType, IFriendKey.RoomTier tier)
        public
        view
        returns (bool)
    {
        uint256 maxAllowed = maxRoomsPerTier[roomType][tier];
        return creatorRoomNonce[creator][roomType][tier] < maxAllowed;
    }

    /**
     * @notice Gets the number of rooms a creator has for a specific type/tier
     */
    function getCreatorRoomCount(address creator, IFriendKey.RoomType roomType, IFriendKey.RoomTier tier)
        public
        view
        returns (uint256)
    {
        return creatorRoomNonce[creator][roomType][tier];
    }

    /**
     * @notice Gets all room IDs created by a creator for a specific type/tier
     */
    function getCreatorRooms(address creator, IFriendKey.RoomType roomType, IFriendKey.RoomTier tier)
        public
        view
        returns (uint256[] memory)
    {
        return creatorRoomsByTier[creator][roomType][tier];
    }

    /**
     * @notice Owner function to update room limits
     * @dev Setting maxRooms to 0 disables room creation for that type/tier
     *      Setting maxRooms > 0 enables room creation with that limit
     */
    function setMaxRoomsPerTier(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier, uint256 maxRooms)
        external
        onlyOwner
    {
        maxRoomsPerTier[roomType][tier] = maxRooms;
        emit MaxRoomsPerTierChanged(roomType, tier, maxRooms);
    }

    /**
     * @notice Enables room creation for a specific type/tier with default limits
     * @dev Convenience function to enable rooms without specifying exact limits
     */
    function enableRoomType(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier) external onlyOwner {
        maxRoomsPerTier[roomType][tier] = 1;
        emit MaxRoomsPerTierChanged(roomType, tier, 1);
    }

    /**
     * @notice Disables room creation for a specific type/tier
     * @dev Sets max rooms to 0, effectively disabling new room creation
     */
    function disableRoomType(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier) external onlyOwner {
        maxRoomsPerTier[roomType][tier] = 0;
        emit MaxRoomsPerTierChanged(roomType, tier, 0);
    }

    /**
     * @notice Batch set limits for multiple room types/tiers
     */
    function batchSetLimits(
        IFriendKey.RoomType[] calldata roomTypes,
        IFriendKey.RoomTier[] calldata tiers,
        uint256[] calldata limits
    ) external onlyOwner {
        require(roomTypes.length == tiers.length && tiers.length == limits.length, "Array length mismatch");

        for (uint256 i = 0; i < roomTypes.length; i++) {
            maxRoomsPerTier[roomTypes[i]][tiers[i]] = limits[i];
            emit MaxRoomsPerTierChanged(roomTypes[i], tiers[i], limits[i]);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
