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
 * @dev This contract works alongside FriendKey to provide room management and some admin
 *      functionality for the FriendKey contract.
 */
contract FriendRoomManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // ============================================
    // CONSTANTS
    // ============================================

    uint256 private constant BPS_SCALE = 10000;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Reference to the main FriendKey contract
    IFriendKey public friendKey;

    // ============ Fee Configuration ============

    /// @notice Trading room fee percentages (in basis points)
    uint16 public devFeePercent;
    uint16 public creatorFeePercent;
    uint16 public tradingPoolFeePercent;

    /// @notice Performance fee percentages (in basis points)
    uint16 public devPerformanceFeePercent;
    uint16 public creatorPerformanceFeePercent;

    /// @notice Social room fee percentages (in basis points)
    uint16 public socialDevFeePercent;
    uint16 public socialCreatorFeePercent;

    /// @notice Fee destination addresses
    address public devFeeDestination;
    address public tradingPoolFeeDestination;

    // ============ Bonding Curve Configuration ============

    /// @notice Bonding curve divisors for different room tiers [Casual, Club, Exclusive]
    uint256[3] public bondingCurveDivisors;

    /// @notice Social room divisors (different pricing for social rooms)
    uint256[3] public socialDivisors;

    // ============ Room Management Configuration ============

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

    // ============================================
    // EVENTS
    // ============================================

    event MaxRoomsPerTierChanged(
        IFriendKey.RoomType indexed roomType, IFriendKey.RoomTier indexed tier, uint256 maxRooms
    );
    event RoomRegistered(
        address indexed creator, IFriendKey.RoomType indexed roomType, IFriendKey.RoomTier indexed tier, uint256 tokenId
    );
    event BondingCurveDivisorsSet(uint256[3] indexed divisors);
    event SocialDivisorsSet(uint256[3] indexed divisors);
    event FeeDestinationsSet(address indexed devDest, address indexed poolDest);
    event FriendKeySet(address indexed friendKey);
    event AuthoritySet(address indexed authority);

    // ============================================
    // CONSTRUCTOR & INITIALIZER
    // ============================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the FriendRoomManager contract
     * @param initialOwner The address that will own the contract
     */
    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        _setDefaultLimits();
        _setDefaultFees();
    }

    // ============================================
    // Custom Modifiers
    // ============================================

    modifier onlyFriendKey() {
        if (msg.sender != address(friendKey)) revert Errors.NotFriendKey();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != authority && msg.sender != owner()) revert Errors.Unauthorized();
        _;
    }

    // ============================================
    // EXTERNAL FUNCTIONS - CONFIGURATION
    // ============================================

    /**
     * @notice Sets the FriendKey contract address
     * @dev Only callable by owner, typically called during FriendKey initialization
     * @param _friendKey Address of the FriendKey contract
     */
    function setFriendKey(address _friendKey) external onlyOwner {
        if (_friendKey == address(0)) revert Errors.ZeroAddress();
        friendKey = IFriendKey(_friendKey);
    }

    /**
     * @notice Sets the authority address
     * @param _authority New authority address
     */
    function setAuthority(address _authority) external onlyOwner {
        if (_authority == address(0)) revert Errors.ZeroAddress();
        authority = _authority;
        emit AuthoritySet(_authority);
    }

    /**
     * @notice Sets the eligibility duration for reward eligibility
     * @param _duration New eligibility duration in seconds
     */
    function setEligibilityDuration(uint256 _duration) external onlyAuthorized {
        eligibilityDuration = _duration;
    }

    // ============================================
    // EXTERNAL FUNCTIONS - FEE MANAGEMENT
    // ============================================

    /**
     * @notice Sets fee destinations for both dev and trading pool
     * @param _devDest Address where dev fees are sent
     * @param _poolDest Address where trading pool fees are sent (usually FriendPool)
     */
    function setFeeDestinations(address _devDest, address _poolDest) external onlyOwner {
        if (_devDest == address(0)) revert Errors.ZeroAddress();
        if (_poolDest == address(0)) revert Errors.ZeroAddress();

        devFeeDestination = _devDest;
        tradingPoolFeeDestination = _poolDest;
        emit FeeDestinationsSet(_devDest, _poolDest);
    }

    /**
     * @notice Sets trading room fees (dev, creator, trading pool)
     * @param _devFee Dev fee in basis points
     * @param _creatorFee Creator fee in basis points
     * @param _poolFee Trading pool fee in basis points
     */
    function setTradingFees(uint16 _devFee, uint16 _creatorFee, uint16 _poolFee) external onlyOwner {
        if (_devFee + _creatorFee + _poolFee > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();

        devFeePercent = _devFee;
        creatorFeePercent = _creatorFee;
        tradingPoolFeePercent = _poolFee;
    }

    /**
     * @notice Sets performance fees (dev, creator)
     * @param _devFee Dev performance fee in basis points
     * @param _creatorFee Creator performance fee in basis points
     */
    function setPerformanceFees(uint16 _devFee, uint16 _creatorFee) external onlyOwner {
        devPerformanceFeePercent = _devFee;
        creatorPerformanceFeePercent = _creatorFee;
    }

    /**
     * @notice Sets social room fees (dev, creator)
     * @param _devFee Social dev fee in basis points
     * @param _creatorFee Social creator fee in basis points
     */
    function setSocialFees(uint16 _devFee, uint16 _creatorFee) external onlyOwner {
        if (_devFee + _creatorFee > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();

        socialDevFeePercent = _devFee;
        socialCreatorFeePercent = _creatorFee;
    }

    // ============================================
    // EXTERNAL FUNCTIONS - BONDING CURVE CONFIG
    // ============================================

    /**
     * @notice Sets bonding curve divisors for trading rooms
     * @param _divisors Array of divisors [Casual, Club, Exclusive]
     */
    function setBondingCurveDivisors(uint256[3] calldata _divisors) external onlyOwner {
        if (_divisors[0] == 0 || _divisors[1] == 0 || _divisors[2] == 0) revert Errors.ZeroDivisor();
        bondingCurveDivisors = _divisors;
        emit BondingCurveDivisorsSet(_divisors);
    }

    /**
     * @notice Sets bonding curve divisors for social rooms
     * @param _divisors Array of divisors [Casual, Club, Exclusive]
     */
    function setSocialDivisors(uint256[3] calldata _divisors) external onlyOwner {
        if (_divisors[0] == 0 || _divisors[1] == 0 || _divisors[2] == 0) revert Errors.ZeroDivisor();
        socialDivisors = _divisors;
        emit SocialDivisorsSet(_divisors);
    }

    // ============================================
    // EXTERNAL FUNCTIONS - ROOM MANAGEMENT
    // ============================================

    /**
     * @notice Checks if a creator can register a room and updates tracking
     * @dev Called by FriendKey before registration
     * @param creator Address of the creator
     * @param roomType Type of room (Trading/Social)
     * @param tier Tier of room (Casual/Club/Exclusive)
     * @param tokenId ID of the token being created
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

    /**
     * @notice Owner function to update room limits
     * @dev Setting maxRooms to 0 disables room creation for that type/tier
     *      Setting maxRooms > 0 enables room creation with that limit
     * @param roomType Type of room
     * @param tier Tier of room
     * @param maxRooms Maximum number of rooms allowed
     */
    function setMaxRoomsPerTier(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier, uint256 maxRooms)
        external
        onlyOwner
    {
        maxRoomsPerTier[roomType][tier] = maxRooms;
        emit MaxRoomsPerTierChanged(roomType, tier, maxRooms);
    }

    /**
     * @notice Enables room creation for a specific type/tier with default limit of 1
     * @dev Convenience function to enable rooms without specifying exact limits
     * @param roomType Type of room
     * @param tier Tier of room
     */
    function enableRoomType(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier) external onlyAuthorized {
        maxRoomsPerTier[roomType][tier] = 1;
        emit MaxRoomsPerTierChanged(roomType, tier, 1);
    }

    /**
     * @notice Disables room creation for a specific type/tier
     * @dev Sets max rooms to 0, effectively disabling new room creation
     * @param roomType Type of room
     * @param tier Tier of room
     */
    function disableRoomType(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier) external onlyAuthorized {
        maxRoomsPerTier[roomType][tier] = 0;
        emit MaxRoomsPerTierChanged(roomType, tier, 0);
    }

    /**
     * @notice Batch set limits for multiple room types/tiers
     * @param roomTypes Array of room types
     * @param tiers Array of room tiers
     * @param limits Array of max room limits
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

    // ============================================
    // PUBLIC/EXTERNAL VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Gets trading fees for trading rooms
     * @return dev Dev fee in basis points
     * @return creator Creator fee in basis points
     * @return pool Trading pool fee in basis points
     */
    function getTradingFees() external view returns (uint16 dev, uint16 creator, uint16 pool) {
        return (devFeePercent, creatorFeePercent, tradingPoolFeePercent);
    }

    /**
     * @notice Gets performance fees
     * @return dev Dev performance fee in basis points
     * @return creator Creator performance fee in basis points
     */
    function getPerformanceFees() external view returns (uint16 dev, uint16 creator) {
        return (devPerformanceFeePercent, creatorPerformanceFeePercent);
    }

    /**
     * @notice Gets social room fees
     * @return dev Social dev fee in basis points
     * @return creator Social creator fee in basis points
     */
    function getSocialFees() external view returns (uint16 dev, uint16 creator) {
        return (socialDevFeePercent, socialCreatorFeePercent);
    }

    /**
     * @notice Gets fee destinations
     * @return dev Dev fee destination address
     * @return pool Trading pool fee destination address
     */
    function getFeeDestinations() external view returns (address dev, address pool) {
        return (devFeeDestination, tradingPoolFeeDestination);
    }

    /**
     * @notice Gets the bonding curve divisor for a specific room type and tier
     * @param roomType Type of room (Trading/Social)
     * @param tier Tier of room (Casual/Club/Exclusive)
     * @return Divisor value for the specified room type and tier
     */
    function getDivisor(IFriendKey.RoomType roomType, IFriendKey.RoomTier tier) external view returns (uint256) {
        if (roomType == IFriendKey.RoomType.Social) {
            return socialDivisors[uint256(tier)];
        }
        return bondingCurveDivisors[uint256(tier)];
    }

    /**
     * @notice Checks if a creator can register another room of a specific type/tier
     * @param creator Address of the creator
     * @param roomType Type of room
     * @param tier Tier of room
     * @return True if creator can register, false otherwise
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
     * @param creator Address of the creator
     * @param roomType Type of room
     * @param tier Tier of room
     * @return Number of rooms created
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
     * @param creator Address of the creator
     * @param roomType Type of room
     * @param tier Tier of room
     * @return Array of token IDs
     */
    function getCreatorRooms(address creator, IFriendKey.RoomType roomType, IFriendKey.RoomTier tier)
        public
        view
        returns (uint256[] memory)
    {
        return creatorRoomsByTier[creator][roomType][tier];
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Updates room tracking when a new room is registered
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
    ) internal {
        creatorRoomNonce[creator][roomType][tier]++;
        creatorRoomsByTier[creator][roomType][tier].push(tokenId);
    }

    /**
     * @notice Sets default room limits for initialization
     * @dev Trading rooms: 1 per tier, Social rooms: 5 per tier
     */
    function _setDefaultLimits() internal {
        // Trading rooms: 1 room per tier
        // Casual rooms: Disabled by default for now
        maxRoomsPerTier[IFriendKey.RoomType.Trading][IFriendKey.RoomTier.Club] = 1;
        maxRoomsPerTier[IFriendKey.RoomType.Trading][IFriendKey.RoomTier.Exclusive] = 1;

        // Social rooms: Disabled by default for now
    }

    /**
     * @notice Sets default fees and configuration for initialization
     */
    function _setDefaultFees() internal {
        devFeePercent = 200; // 2%
        creatorFeePercent = 200; // 2%
        tradingPoolFeePercent = 600; // 6%

        // Default performance fees
        devPerformanceFeePercent = 500; // 5%
        creatorPerformanceFeePercent = 1500; // 15%

        // Default social fees (lower than trading)
        socialDevFeePercent = 200; // 2%
        socialCreatorFeePercent = 200; // 2%

        // Default bonding curve divisors [Casual, Club, Exclusive]
        bondingCurveDivisors = [4000, 40, 4];
        socialDivisors = [8000, 80, 8]; // Higher divisors = lower prices

        // Default eligibility duration
        eligibilityDuration = 1 days;
    }

    /**
     * @dev Authorizes contract upgrades - only callable by owner
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
