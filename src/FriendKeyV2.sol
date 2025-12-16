// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {
    ERC1155BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {
    ERC1155SupplyUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IFriendPool} from "./interfaces/IFriendPool.sol";
import {FriendStake} from "./FriendStake.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Errors} from "./libraries/Errors.sol";
import {BondingCurveLib} from "./libraries/BondingCurveLib.sol";
import {IFriendRoomManager} from "./interfaces/IFriendRoomManager.sol";
import {IFriendKey} from "./interfaces/IFriendKey.sol";

/**
 * @title FriendKey
 * @author FriendDotSpace
 * @custom:oz-upgrades-from FriendKey
 * @notice A social token platform that allows creators to issue their own tokenized shares using bonding curves
 * @dev This contract implements an ERC-1155 based social token system with the following features:
 *      - Bonding curve pricing mechanism for token purchases/sales
 *      - Multi-tier room system (Club, Exclusive) with different pricing curves
 *      - Fee distribution system (dev fees, creator fees, trading pool fees)
 *      - Staking integration for token holders
 *      - Cross-chain functionality through FriendPool integration
 *      - Upgradeable contract using UUPS proxy pattern
 */
contract FriendKeyV2 is
    Initializable,
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    UUPSUpgradeable,
    EIP712Upgradeable
{
    using SafeERC20 for IERC20Metadata;
    using Strings for uint256;
    using ECDSA for bytes32;

    /// @notice Enum defining different room types
    /// @dev Determines the functionality and features available in the room
    enum RoomType {
        Trading, // Full trading functionality with staking pools and cross-chain features
        Social // Social-only functionality without staking
    }

    /// @notice Enum defining different room tiers with varying bonding curve parameters
    /// @dev Each tier has a different divisor that affects the pricing curve steepness
    enum RoomTier {
        Casual, // Most affordable tier with highest divisor (4000)
        Club, // Medium tier with moderate divisor (40)
        Exclusive // Premium tier with lowest divisor (4) - highest prices
    }

    /// @dev Counter for generating unique token IDs
    uint256 private _nextTokenId;

    /// @notice Basis point scale for percentage calculations (10000 = 100%)
    uint256 public BPS_SCALE;

    // Fee storage moved to RoomManager
    /// @notice Address of the FriendStake beacon contract for beacon proxy cloning
    address public friendStakeBeacon;

    /// @notice The ERC20 token used for bonding curve transactions (e.g., USDC)
    IERC20Metadata public bondingToken;
    /// @notice Price unit based on bonding token decimals (e.g., 10^6 for USDC)
    uint256 public bondingTokenPriceUnit;

    /// @notice Mapping from token ID to creator's address
    mapping(uint256 => address) public creatorByTokenId;
    /// @notice Mapping from token ID to its staking pool contract address
    mapping(uint256 => address) public stakingPoolByTokenId;
    /// @notice Mapping from creator address to their bonding curve reserves
    mapping(address => uint256) public bondingCurveReserves;

    /// @notice Tracks when users first acquired tokens for eligibility purposes
    /// @dev Maps tokenId => userAddress => timestamp
    mapping(uint256 => mapping(address => uint256)) public keyHoldingSince;

    /// @notice Mapping from token ID to its room tier
    mapping(uint256 => RoomTier) public roomTiers;

    // Bonding curve divisors moved to RoomManager

    /// @notice Temporary mapping to track sold amounts for each token ID during batch transfers
    /// @dev Used internally in _update to determine if a user's balance reaches zero after a transfer
    mapping(uint256 => uint256) private _sold;

    /// @notice Optional metadata mapping for each token ID
    /// @dev Can be used to store additional information about each token
    mapping(uint256 => string) private _metadata;

    /// @notice Replay protection nonces for registerCreator authorizations
    mapping(address => uint256) public registerCreatorNonces;

    // Tier limits managed by RoomManager

    /// @notice Mapping from token ID to its room type (for V2 compatibility)
    /// @dev All existing tokens are Trading type by default
    mapping(uint256 => RoomType) public roomTypes;

    /// @notice Reference to the FriendRoomManager contract for room limit enforcement
    address public roomManager;

    /// @dev keccak256("RegisterCreator(address account,uint8 roomType,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)")
    bytes32 private constant _REGISTER_CREATOR_TYPEHASH =
        keccak256(
            "RegisterCreator(address account,uint8 roomType,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)"
        );

    /// @dev Private address authorized to sign room creation requests
    address private _signee;

    uint256[50] private __gap;

    /// @notice Emitted when tokens are bought or sold
    /// @param tokenId The ID of the token being traded
    /// @param trader The address executing the trade
    /// @param subject The creator/subject of the token
    /// @param isBuy True for buy, false for sell
    /// @param shareAmount Number of shares traded
    /// @param tokenAmount Amount of bonding tokens involved
    /// @param supply Total supply after the trade
    event Trade(
        uint256 indexed tokenId,
        address indexed trader,
        address indexed subject,
        bool isBuy,
        uint256 shareAmount,
        uint256 tokenAmount,
        uint256 supply
    );

    /// @notice Emitted when a new creator key is created
    /// @param tokenId The unique ID assigned to the creator's token
    /// @param creator The address of the creator
    /// @param stakingPool The address of the created staking pool
    /// @param tokenURI The metadata URI for the token
    /// @param initialSupply The initial token supply minted to creator
    /// @param tier The room tier selected for this creator
    event KeyCreated(
        uint256 indexed tokenId,
        address indexed creator,
        address indexed stakingPool,
        string tokenURI,
        uint256 initialSupply,
        RoomTier tier,
        RoomType roomType
    );

    /// @notice Emitted when tokens are staked
    /// @param tokenId The ID of the token being staked
    /// @param staker The address staking the tokens
    /// @param amount The amount of tokens staked
    event KeyStaked(uint256 indexed tokenId, address indexed staker, address indexed stakingPool, uint256 amount);

    /// @notice Emitted when tokens are unstaked
    /// @param tokenId The ID of the token being unstaked
    /// @param staker The address unstaking the tokens
    /// @param amount The amount of tokens unstaked
    event KeyUnstaked(uint256 indexed tokenId, address indexed staker, address indexed stakingPool, uint256 amount);
    event CreatorRewarded(uint256 indexed tokenId, address indexed creator, uint256 amount);

    // --- Owner management events ---
    enum Target {
        DevFee,
        CreatorFee,
        TradingPoolFee,
        DevPerformanceFee,
        CreatorPerformanceFee
    }

    /// @notice Emitted when the target fee destination is changed
    /// @param newDestination The new address for target fees
    event FeeDestinationChanged(address indexed newDestination, Target target);
    /// @notice Emitted when the target fee percentage is changed
    /// @param newPercent The new target fee percentage in basis points
    event FeePercentChanged(uint256 newPercent, Target target);
    /// @notice Emitted when the signee address is changed
    /// @param newSignee The new signee address
    event SigneeChanged(address indexed newSignee);
    /// @notice Emitted when the is tier allowed is changed
    /// @param roomType The room type to change the allowed tier for
    /// @param tier The tier to change the allowed status for
    /// @param isAllowed The new allowed status
    event IsTierAllowedChanged(RoomType indexed roomType, RoomTier indexed tier, bool isAllowed);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with required parameters
     * @dev This function replaces the constructor in upgradeable contracts
     * @param initialOwner The address that will own the contract
     * @param _bondingTokenAddress Address of the ERC20 token used for trading (e.g., USDC)
     * @param _friendStakeBeacon Address of the FriendStake beacon for beacon proxy cloning
     * @param _roomManager Address of the FriendRoomManager contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    function initialize(
        address initialOwner,
        address _bondingTokenAddress,
        address _friendStakeBeacon,
        address _roomManager
    ) public initializer {
        __ERC1155_init("");
        __Ownable_init(initialOwner);
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __UUPSUpgradeable_init();
        __EIP712_init("FriendKey", "1");

        BPS_SCALE = 10000;
        if (_bondingTokenAddress == address(0)) revert Errors.ZeroAddress();
        if (_friendStakeBeacon == address(0)) revert Errors.ZeroAddress();
        if (_roomManager == address(0)) revert Errors.ZeroAddress();

        uint8 decimals = IERC20Metadata(_bondingTokenAddress).decimals();
        if (decimals == 0) revert Errors.InvalidDecimals();
        bondingTokenPriceUnit = 10 ** decimals;
        bondingToken = IERC20Metadata(_bondingTokenAddress);
        friendStakeBeacon = _friendStakeBeacon;
        roomManager = _roomManager;
    }

    /// @notice Modifier to ensure RoomManager is set before calling functions that depend on it
    modifier roomManagerSet() {
        if (roomManager == address(0)) revert Errors.RoomManagerNotSet();
        _;
    }

    /// @notice Modifier to check if contract is paused
    modifier whenNotPaused() {
        if (roomManager != address(0)) {
            if (IFriendRoomManager(roomManager).paused()) revert Errors.ContractPaused();
        }
        _;
    }

    /**
     * @notice Sets the base URI for token metadata
     * @dev Only callable by contract owner
     * @param newuri The new base URI string
     */
    function setURI(string memory newuri) external onlyOwner {
        _setURI(newuri);
    }

    function setSignee(address signee) public onlyOwner {
        if (signee == address(0)) revert Errors.ZeroAddress();
        _signee = signee;
        emit SigneeChanged(signee);
    }

    function setRoomManager(address _roomManager) external onlyOwner {
        if (_roomManager == address(0)) revert Errors.ZeroAddress();
        roomManager = _roomManager;
    }

    // --- Fee and Creator Management ---

    // Fee helpers - simplified for size
    function _getTradingFees() internal view roomManagerSet returns (uint16 dev, uint16 creator, uint16 pool) {
        return IFriendRoomManager(roomManager).getTradingFees();
    }

    function getPerformanceFees() public view roomManagerSet returns (uint16 dev, uint16 creator) {
        return IFriendRoomManager(roomManager).getPerformanceFees();
    }

    function _getSocialFees() internal view roomManagerSet returns (uint16 dev, uint16 creator) {
        return IFriendRoomManager(roomManager).getSocialFees();
    }

    function getFeeDestinations() public view roomManagerSet returns (address dev, address pool) {
        return IFriendRoomManager(roomManager).getFeeDestinations();
    }

    /**
     * @notice Registers a new creator with specified tier and additional keys
     * @dev Requires an off-chain EIP-712 signature from the contract owner authorizing the registration.
     *      Creates a new token ID, deploys a staking pool, and mints initial supply
     * @param tier The room tier for the creator (affects bonding curve pricing)
     * @param additionalKeys Number of additional keys to mint beyond the initial key
     * @param metadata Arbitrary metadata string (e.g., IPFS hash or identifier)
     * @param signature Owner signature authorizing the registration parameters
     * @return The newly created token ID
     */
    function registerCreator(RoomTier tier, uint256 additionalKeys, string calldata metadata, bytes calldata signature)
        public
        virtual
        whenNotPaused
        returns (uint256)
    {
        // Tier allowance now checked via FriendRoomManager
        _verifyRegisterCreatorSignature(msg.sender, RoomType.Trading, tier, additionalKeys, metadata, signature);
        return _registerCreator(RoomType.Trading, tier, additionalKeys, metadata);
    }

    /**
     * @notice Registers a new creator with default settings (Club tier, no additional keys)
     * @dev Requires an owner signature authorizing the caller
     * @param metadata Arbitrary metadata string (e.g., IPFS hash or identifier)
     * @param signature Owner signature authorizing the registration parameters
     * @return The newly created token ID
     */
    function registerCreator(string calldata metadata, bytes calldata signature)
        public
        virtual
        whenNotPaused
        returns (uint256)
    {
        return registerCreator(RoomTier.Club, 0, metadata, signature);
    }

    /**
     * @notice Registers a creator for social rooms with a specific tier
     * @dev Social rooms have different pricing and no staking/trading pool
     */
    function registerSocialCreator(
        RoomTier tier,
        uint256 additionalKeys,
        string calldata metadata,
        bytes calldata signature
    ) public virtual whenNotPaused returns (uint256) {
        _verifyRegisterCreatorSignature(msg.sender, RoomType.Social, tier, additionalKeys, metadata, signature);
        return _registerCreator(RoomType.Social, tier, additionalKeys, metadata);
    }

    /**
     * @notice Registers a creator for social rooms with default Club tier
     */
    function registerSocialCreator(string calldata metadata, bytes calldata signature)
        public
        virtual
        whenNotPaused
        returns (uint256)
    {
        return registerSocialCreator(RoomTier.Club, 0, metadata, signature);
    }

    function _registerCreator(RoomType roomType, RoomTier tier, uint256 additionalKeys, string calldata metadata)
        internal
        virtual
        roomManagerSet
        returns (uint256)
    {
        address creator = msg.sender;
        uint256 id = ++_nextTokenId;

        try IFriendRoomManager(roomManager).checkAndUpdateRoomRegistration(
            creator, IFriendKey.RoomType(uint8(roomType)), IFriendKey.RoomTier(uint8(tier)), id
        ) {}
        catch {
            revert Errors.RoomLimitExceeded();
        }
        creatorByTokenId[id] = creator;
        roomTiers[id] = tier;
        roomTypes[id] = roomType;

        if (bytes(metadata).length > 0) {
            _metadata[id] = metadata;
        }
        string memory tokenUri = uri(id);

        if (roomType == RoomType.Trading) {
            bytes memory parameters = abi.encodeWithSelector(
                FriendStake.initialize.selector,
                owner(),
                address(this),
                address(bondingToken),
                id,
                IFriendRoomManager(roomManager).authority(),
                IFriendRoomManager(roomManager).eligibilityDuration()
            );
            address friendStake = address(new BeaconProxy(friendStakeBeacon, parameters));
            stakingPoolByTokenId[id] = friendStake;
        }

        buyShares(id, 1 + additionalKeys, type(uint256).max); // Mint 1 + additional shares
        emit KeyCreated(id, creator, stakingPoolByTokenId[id], tokenUri, 1 + additionalKeys, tier, roomType);
        return id;
    }

    function _verifyRegisterCreatorSignature(
        address account,
        RoomType roomType,
        RoomTier tier,
        uint256 additionalKeys,
        string calldata metadata,
        bytes calldata signature
    ) internal virtual {
        uint256 nonce = registerCreatorNonces[account];
        bytes32 metadataHash = keccak256(bytes(metadata));
        bytes32 structHash = keccak256(
            abi.encode(_REGISTER_CREATOR_TYPEHASH, account, uint8(roomType), uint8(tier), additionalKeys, nonce, metadataHash)
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = digest.recover(signature);
        if (recoveredSigner != owner() && (_signee == address(0) || recoveredSigner != _signee)) {
            revert Errors.UnauthorizedRegisterSignature();
        }
        registerCreatorNonces[account] = nonce + 1;
    }

    /**
     * @notice Returns the metadata URI for a specific token
     * @dev Concatenates base URI with token ID if base URI is set
     * @param tokenId The token ID to get URI for
     * @return The complete metadata URI for the token
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        address creator = creatorByTokenId[tokenId];
        if (creator == address(0)) revert Errors.CreatorNotRegistered();
        string memory tokenURI = tokenId.toString();
        string memory base = super.uri(tokenId);

        string memory storedMetadata = _metadata[tokenId];
        if (bytes(storedMetadata).length > 0) {
            return storedMetadata;
        }

        // If token URI is set, concatenate base URI and tokenURI (via string.concat).
        return bytes(base).length > 0 ? string.concat(base, tokenURI) : base;
    }

    // --- Pricing Logic ---

    /**
     * @notice Calculates the price for a given supply and amount using bonding curve formula
     * @dev Uses polynomial pricing: price = (sum of squares * priceUnit) / divisor
     * @param supply Current token supply
     * @param amount Number of tokens to price
     * @param divisor Divisor used for the pricing curve (affects steepness)
     * @return The calculated price in bonding token units
     */
    function getPrice(uint256 supply, uint256 amount, uint256 divisor) public view returns (uint256) {
        return BondingCurveLib.getPrice(supply, amount, divisor, bondingTokenPriceUnit);
    }

    /**
     * @notice Gets the bonding curve divisor for a specific token ID
     * @dev Lower divisor = higher prices. Used to differentiate room tiers
     * @param id The token ID to get divisor for
     * @return The divisor value for the token's room tier
     */
    function getDivisor(uint256 id) public view virtual roomManagerSet returns (uint256) {
        return IFriendRoomManager(roomManager)
            .getDivisor(IFriendKey.RoomType(uint8(roomTypes[id])), IFriendKey.RoomTier(uint8(roomTiers[id])));
    }

    /**
     * @notice Calculates the price to buy a specific amount of tokens (before fees)
     * @param id The token ID to buy
     * @param amount Number of tokens to buy
     * @return The price in bonding token units before fees
     */
    function getBuyPrice(uint256 id, uint256 amount) public view virtual roomManagerSet returns (uint256) {
        uint256 divisor = getDivisor(id);
        return BondingCurveLib.getBuyPrice(totalSupply(id), amount, divisor, bondingTokenPriceUnit);
    }

    /**
     * @notice Calculates the price to sell a specific amount of tokens (before fees)
     * @param id The token ID to sell
     * @param amount Number of tokens to sell
     * @return The price in bonding token units before fees
     */
    function getSellPrice(uint256 id, uint256 amount) public view virtual roomManagerSet returns (uint256) {
        if (totalSupply(id) < amount) revert Errors.AmountExceedsSupply();
        uint256 divisor = getDivisor(id);
        return BondingCurveLib.getSellPrice(totalSupply(id), amount, divisor, bondingTokenPriceUnit);
    }

    /**
     * @notice Calculates the total cost to buy tokens including all fees
     * @param id The token ID to buy
     * @param amount Number of tokens to buy
     * @return The total cost including base price and all fees
     */
    function getBuyPriceAfterFee(uint256 id, uint256 amount) public view virtual returns (uint256) {
        uint256 divisor = getDivisor(id);
        if (roomTypes[id] == RoomType.Social) {
            (uint16 socialDevFee, uint16 socialCreatorFee) = _getSocialFees();
            return BondingCurveLib.getBuyPriceAfterFee(
                totalSupply(id), amount, divisor, bondingTokenPriceUnit, socialDevFee, socialCreatorFee, 0, BPS_SCALE
            );
        }
        (uint16 devFee, uint16 creatorFee, uint16 poolFee) = _getTradingFees();
        return BondingCurveLib.getBuyPriceAfterFee(
            totalSupply(id), amount, divisor, bondingTokenPriceUnit, devFee, creatorFee, poolFee, BPS_SCALE
        );
    }

    /**
     * @notice Calculates the proceeds from selling tokens after deducting all fees
     * @param id The token ID to sell
     * @param amount Number of tokens to sell
     * @return The net proceeds after deducting all fees
     */
    function getSellPriceAfterFee(uint256 id, uint256 amount) public view virtual returns (uint256) {
        uint256 divisor = getDivisor(id);
        if (roomTypes[id] == RoomType.Social) {
            (uint16 socialDevFee, uint16 socialCreatorFee) = _getSocialFees();
            return BondingCurveLib.getSellPriceAfterFee(
                totalSupply(id), amount, divisor, bondingTokenPriceUnit, socialDevFee, socialCreatorFee, 0, BPS_SCALE
            );
        }
        (uint16 devFee, uint16 creatorFee, uint16 poolFee) = _getTradingFees();
        return BondingCurveLib.getSellPriceAfterFee(
            totalSupply(id), amount, divisor, bondingTokenPriceUnit, devFee, creatorFee, poolFee, BPS_SCALE
        );
    }

    // --- Buy and Sell Shares ---

    /**
     * @notice Purchases tokens for a specific creator using bonding curve pricing with slippage protection
     * @dev Calculates price, collects fees, mints tokens, and distributes payments
     * @param tokenId The ID of the creator's token to buy
     * @param amount Number of tokens to purchase
     * @param maxSpend Maximum amount of bonding tokens to spend. Use type(uint256).max to disable protection
     */
    function buyShares(uint256 tokenId, uint256 amount, uint256 maxSpend) public virtual whenNotPaused {
        if (amount == 0) revert Errors.AmountMustBeGreaterThanZero();
        address creatorAddress = creatorByTokenId[tokenId];
        if (creatorAddress == address(0)) revert Errors.CreatorNotRegistered();

        uint256 currentSupply = totalSupply(tokenId);
        if (currentSupply == 0) {
            if (msg.sender != creatorAddress) revert Errors.OnlyCreatorCanBuyFirstShare();
        }

        uint256 price = getPrice(currentSupply, amount, getDivisor(tokenId));
        uint256 devFee;
        uint256 creatorFee;
        uint256 tradingPoolFee;

        if (roomTypes[tokenId] == RoomType.Social) {
            (uint16 socialDevFee, uint16 socialCreatorFee) = _getSocialFees();
            (devFee, creatorFee, tradingPoolFee) =
                BondingCurveLib.calculateFees(price, socialDevFee, socialCreatorFee, 0, BPS_SCALE);
        } else {
            (uint16 tradingDevFee, uint16 tradingCreatorFee, uint16 tradingPoolFeePercent) = _getTradingFees();
            (devFee, creatorFee, tradingPoolFee) = BondingCurveLib.calculateFees(
                price, tradingDevFee, tradingCreatorFee, tradingPoolFeePercent, BPS_SCALE
            );
        }
        uint256 totalCost = price + devFee + creatorFee + tradingPoolFee;

        // Slippage protection: ensure total cost doesn't exceed maxSpend
        if (maxSpend == 0) revert Errors.SlippageProtectionRequired();
        if (maxSpend != type(uint256).max && totalCost > maxSpend) {
            revert Errors.SlippageExceededMaxSpend();
        }

        bondingCurveReserves[creatorAddress] += price;

        _mint(msg.sender, tokenId, amount, "");

        if (totalCost > 0) {
            // Check the allowance and balance first
            uint256 allowance = bondingToken.allowance(msg.sender, address(this));
            if (allowance < totalCost) revert Errors.InsufficientAllowance();
            uint256 balance = bondingToken.balanceOf(msg.sender);
            if (balance < totalCost) revert Errors.InsufficientBalance();
            // Transfer the bonding token from the user to this contract
            bondingToken.safeTransferFrom(msg.sender, address(this), totalCost);
        }

        emit Trade(tokenId, msg.sender, creatorAddress, true, amount, price, currentSupply + amount);
        (address devFeeDestination, address poolFeeDestination) = getFeeDestinations();

        if (devFee > 0) {
            if (devFeeDestination == address(0)) revert Errors.ZeroAddress();
            bondingToken.safeTransfer(devFeeDestination, devFee);
        }
        if (creatorFee > 0) {
            emit CreatorRewarded(tokenId, creatorAddress, creatorFee);
            bondingToken.safeTransfer(creatorAddress, creatorFee);
        }
        if (tradingPoolFee > 0) {
            if (poolFeeDestination == address(0)) revert Errors.ZeroAddress();
            _transferToPool(tokenId, tradingPoolFee);
        }
    }

    /**
     * @notice Sells tokens for a specific creator using bonding curve pricing with slippage protection
     * @dev Burns tokens, calculates proceeds after fees, and transfers payment to seller
     * @param tokenId The ID of the creator's token to sell
     * @param amount Number of tokens to sell
     * @param minReceive Minimum amount of bonding tokens to receive (0 = no protection)
     */
    function sellShares(uint256 tokenId, uint256 amount, uint256 minReceive) public virtual whenNotPaused {
        if (amount == 0) revert Errors.AmountMustBeGreaterThanZero();
        address creatorAddress = creatorByTokenId[tokenId];
        if (creatorAddress == address(0)) revert Errors.CreatorNotRegistered();
        if (balanceOf(msg.sender, tokenId) < amount) revert Errors.InsufficientShares();

        uint256 currentSupply = totalSupply(tokenId);
        if (currentSupply <= amount) revert Errors.CannotSellAllShares();

        (address devFeeDestination, address poolFeeDestination) = getFeeDestinations();

        uint256 price = getPrice(currentSupply - amount, amount, getDivisor(tokenId));
        uint256 devFee;
        uint256 creatorFee;
        uint256 tradingPoolFee;

        if (roomTypes[tokenId] == RoomType.Social) {
            (uint16 socialDevFee, uint16 socialCreatorFee) = _getSocialFees();
            (devFee, creatorFee, tradingPoolFee) =
                BondingCurveLib.calculateFees(price, socialDevFee, socialCreatorFee, 0, BPS_SCALE);
        } else {
            (uint16 tradingDevFee, uint16 tradingCreatorFee, uint16 tradingPoolFeePercent) = _getTradingFees();
            (devFee, creatorFee, tradingPoolFee) = BondingCurveLib.calculateFees(
                price, tradingDevFee, tradingCreatorFee, tradingPoolFeePercent, BPS_SCALE
            );
        }

        uint256 totalFees = devFee + creatorFee + tradingPoolFee;
        uint256 proceeds = price > totalFees ? price - totalFees : 0;

        // Slippage protection: ensure proceeds meet minimum requirement
        if (minReceive > 0 && proceeds < minReceive) {
            revert Errors.SlippageExceededMinReceive();
        }

        bondingCurveReserves[creatorAddress] -= price;
        emit Trade(tokenId, msg.sender, creatorAddress, false, amount, price, currentSupply - amount);

        _burn(msg.sender, tokenId, amount);

        if (proceeds > 0) {
            bondingToken.safeTransfer(msg.sender, proceeds);
        }
        if (devFee > 0) {
            if (devFeeDestination == address(0)) revert Errors.ZeroAddress();
            bondingToken.safeTransfer(devFeeDestination, devFee);
        }
        if (creatorFee > 0) {
            emit CreatorRewarded(tokenId, creatorAddress, creatorFee);
            bondingToken.safeTransfer(creatorAddress, creatorFee);
        }
        if (tradingPoolFee > 0) {
            if (poolFeeDestination == address(0)) revert Errors.ZeroAddress();
            _transferToPool(tokenId, tradingPoolFee);
        }
    }

    /**
     * @notice Stakes tokens in the associated staking pool for rewards
     * @dev Transfers tokens from user to staking pool and updates holding timestamp
     * @param tokenId The ID of the token to stake
     * @param amount Number of tokens to stake
     */
    function stake(uint256 tokenId, uint256 amount) public virtual whenNotPaused {
        // @dev: since by default social rooms don't have a staking pool (address(0)), we don't need to check for that
        if (amount == 0) revert Errors.AmountMustBeGreaterThanZero();
        if (balanceOf(msg.sender, tokenId) < amount) revert Errors.InsufficientShares();
        address stakingPoolAddress = stakingPoolByTokenId[tokenId];
        if (stakingPoolAddress == address(0)) revert Errors.StakingPoolNotRegistered();
        emit KeyStaked(tokenId, msg.sender, stakingPoolAddress, amount);

        FriendStake stakingPool = FriendStake(stakingPoolAddress);
        if (!stakingPool.isOpenForStaking()) revert Errors.StakingPoolNotOpen();

        _safeTransferFrom(msg.sender, stakingPoolAddress, tokenId, amount, "");
    }

    /**
     * @notice Unstakes tokens from the staking pool
     * @dev Calls the staking pool to transfer tokens back to user
     * @param tokenId The ID of the token to unstake
     * @param amount Number of tokens to unstake
     */
    function unstake(uint256 tokenId, uint256 amount) public virtual whenNotPaused {
        if (amount == 0) revert Errors.AmountMustBeGreaterThanZero();
        // since by default social rooms don't have a staking pool (address(0)), we don't need to check for that
        address stakingPoolAddress = stakingPoolByTokenId[tokenId];
        if (stakingPoolAddress == address(0)) revert Errors.StakingPoolNotRegistered();

        FriendStake stakingPool = FriendStake(stakingPoolAddress);
        if (!stakingPool.isOpenForStaking()) revert Errors.StakingPoolNotOpen();

        emit KeyUnstaked(tokenId, msg.sender, stakingPoolAddress, amount);

        stakingPool.unstake(amount, msg.sender);
    }

    /**
     * @notice Internal function to transfer fees to the trading pool
     * @dev Attempts to call pull() on the pool contract, falls back to direct transfer
     * @param tokenId The token ID associated with the fee
     * @param tradingPoolFee Amount of tokens to transfer
     */
    function _transferToPool(uint256 tokenId, uint256 tradingPoolFee) internal virtual {
        (address devDest, address poolDest) = getFeeDestinations();
        if (roomTypes[tokenId] == RoomType.Social) {
            bondingToken.safeTransfer(devDest, tradingPoolFee);
            return;
        }
        // Check if the destination has code (is a contract)
        if (poolDest.code.length > 0) {
            // try to approve and pull from the trading pool otherwise transfer
            bondingToken.forceApprove(poolDest, tradingPoolFee);
            try IFriendPool(poolDest).pull(tokenId, tradingPoolFee) {
            // If the pull succeeds, we don't need to do anything else
            }
            catch {
                bondingToken.safeTransfer(poolDest, tradingPoolFee);
            }
        } else {
            // If it's an EOA, just transfer the tokens
            bondingToken.safeTransfer(poolDest, tradingPoolFee);
        }
    }

    /**
     * @notice Checks if a user is eligible for certain actions based on holding time
     * @param tokenId The ID of the token to check
     * @param user The address of the user to check
     * @return True if the user has held tokens for the required time period
     */
    function isUserEligible(uint256 tokenId, address user) public view returns (bool) {
        uint256 holdingSince = getKeyHoldingSince(tokenId, user);
        if (holdingSince == 0) revert Errors.UserDoesNotHoldToken();
        return block.timestamp >= holdingSince + 24 hours; // Example: 1 day eligibility
    }

    /**
     * @notice Returns since when a user has been continuously holding tokens
     * @param tokenId The ID of the token to check
     * @param user The address of the user to check
     * @return The timestamp when the user first obtained the token, or 0 if they don't hold any
     */
    function getKeyHoldingSince(uint256 tokenId, address user) public view returns (uint256) {
        return keyHoldingSince[tokenId][user];
    }

    /**
     * @notice Checks if a creator can register a room with a specific tier
     * @param creator The address of the creator to check
     * @param roomType The room type to check
     * @param tier The room tier to check availability for
     * @return True if the creator can still register this tier, false if already used
     */
    function canRegisterRoom(address creator, RoomType roomType, RoomTier tier)
        public
        view
        virtual
        roomManagerSet
        returns (bool)
    {
        return IFriendRoomManager(roomManager)
            .canRegisterRoom(creator, IFriendKey.RoomType(uint8(roomType)), IFriendKey.RoomTier(uint8(tier)));
    }

    /**
     * @dev Authorizes contract upgrades - only callable by owner
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // The following functions are overrides required by Solidity.

    /**
     * @dev Internal function to handle token transfers and update holding timestamps
     * @param from Address sending the tokens (address(0) for minting)
     * @param to Address receiving the tokens (address(0) for burning)
     * @param ids Array of token IDs being transferred
     * @param values Array of amounts being transferred
     */
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            _sold[tokenId] += values[i];

            // Handle recipient (to) - for mint and transfer operations
            if (to != address(0) && values[i] > 0 && balanceOf(to, tokenId) == 0) {
                keyHoldingSince[tokenId][to] = block.timestamp;
            }

            // Handle sender (from) - reset timestamp if they no longer hold the token
            if (from != address(0) && balanceOf(from, tokenId) == _sold[tokenId]) {
                keyHoldingSince[tokenId][from] = 0;
            }
        }

        for (uint256 i = 0; i < ids.length; i++) {
            delete _sold[ids[i]];
        }

        // Call super last to ensure all state changes are applied
        super._update(from, to, ids, values);
    }
}
