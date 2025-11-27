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

/**
 * @title FriendKey
 * @author FriendDotSpace
 * @notice A social token platform that allows creators to issue their own tokenized shares using bonding curves
 * @dev This contract implements an ERC-1155 based social token system with the following features:
 *      - Bonding curve pricing mechanism for token purchases/sales
 *      - Multi-tier room system (Club, Exclusive) with different pricing curves
 *      - Fee distribution system (dev fees, creator fees, trading pool fees)
 *      - Staking integration for token holders
 *      - Cross-chain functionality through FriendPool integration
 *      - Upgradeable contract using UUPS proxy pattern
 */
contract FriendKey is
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

    /// @notice Enum defining different room tiers with varying bonding curve parameters
    /// @dev Each tier has a different divisor that affects the pricing curve steepness
    enum RoomTier {
        Club, // Medium tier with moderate divisor (40)
        Exclusive // Premium tier with lowest divisor (4) - highest prices
    }

    /// @dev Counter for generating unique token IDs
    uint256 private _nextTokenId;

    /// @notice Basis point scale for percentage calculations (10000 = 100%)
    uint256 public BPS_SCALE;

    /// @notice Address where development fees are sent
    address public devFeeDestination;
    /// @notice Percentage of each trade sent as development fee (in basis points)
    uint256 public devFeePercent;
    /// @notice Percentage of each trade sent to creator (in basis points)
    uint256 public creatorFeePercent;
    /// @notice Address where trading pool fees are sent (usually FriendPool contract)
    address public tradingPoolFeeDestination;
    /// @notice Percentage of each trade sent as trading pool fee (in basis points)
    uint256 public tradingPoolFeePercent;
    /// @notice Development performance fee percentage (in basis points)
    uint256 public devPerformanceFeePercent;
    /// @notice Creator performance fee percentage (in basis points)
    uint256 public creatorPerformanceFeePercent;
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

    /// @notice Array of divisors for different room tiers [Club, Exclusive]
    /// @dev Lower divisor = higher prices. Used in bonding curve calculations
    uint256[] public bondingCurveDivisors;

    /// @notice Temporary mapping to track sold amounts for each token ID during batch transfers
    /// @dev Used internally in _update to determine if a user's balance reaches zero after a transfer
    mapping(uint256 => uint256) private _sold;

    /// @notice Address with authority to lock staking in FriendStake contracts
    address public authority;

    /// @notice Duration that a stake must be held to be eligible for rewards
    uint256 public eligibilityDuration;

    /// @notice Optional metadata mapping for each token ID
    /// @dev Can be used to store additional information about each token
    mapping(uint256 => string) private _metadata;

    /// @notice Replay protection nonces for registerCreator authorizations
    mapping(address => uint256) public registerCreatorNonces;

    /// @notice Mapping from creator address to their tier used status
    /// @dev Maps creatorAddress => tier => bool
    mapping(address => mapping(RoomTier => bool)) public creatorTierUsed;

    /// @dev keccak256("RegisterCreator(address account,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)")
    bytes32 private constant _REGISTER_CREATOR_TYPEHASH =
        keccak256("RegisterCreator(address account,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)");

    /// @dev Private address authorized to sign room creation requests
    address private _signee;

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
        RoomTier tier
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with required parameters
     * @dev This function replaces the constructor in upgradeable contracts
     * @param initialOwner The address that will own the contract
     * @param _devFeeDestination Address where development fees are sent
     * @param _devFeePercent Development fee percentage (in basis points)
     * @param _creatorFeePercent Creator fee percentage (in basis points)
     * @param _tradingPoolFeeDestination Address where trading pool fees are sent
     * @param _tradingPoolFeePercent Trading pool fee percentage (in basis points)
     * @param _devPerformanceFeePercent Development performance fee percentage
     * @param _creatorPerformanceFeePercent Creator performance fee percentage
     * @param _bondingTokenAddress Address of the ERC20 token used for trading (e.g., USDC)
     * @param _friendStakeBeacon Address of the FriendStake beacon for beacon proxy cloning
     * @param _authority Address with authority to lock staking
     * @param _eligibilityDuration Duration that a stake must be held to be eligible for rewards
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    function initialize(
        address initialOwner,
        address _devFeeDestination,
        uint256 _devFeePercent,
        uint256 _creatorFeePercent,
        address _tradingPoolFeeDestination,
        uint256 _tradingPoolFeePercent,
        uint256 _devPerformanceFeePercent,
        uint256 _creatorPerformanceFeePercent,
        address _bondingTokenAddress,
        address _friendStakeBeacon,
        address _authority,
        uint256 _eligibilityDuration
    ) public initializer {
        __ERC1155_init("");
        __Ownable_init(initialOwner);
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __UUPSUpgradeable_init();
        __EIP712_init("FriendKey", "1");

        BPS_SCALE = 10000;

        if (_devFeePercent + _creatorFeePercent + _tradingPoolFeePercent > BPS_SCALE) {
            revert Errors.TotalFeePercentTooHigh();
        }
        if (_bondingTokenAddress == address(0)) revert Errors.ZeroAddress();
        if (_devFeeDestination == address(0)) revert Errors.ZeroAddress();
        if (_friendStakeBeacon == address(0)) revert Errors.ZeroAddress();
        if (_authority == address(0)) revert Errors.ZeroAddress();
        if (_eligibilityDuration == 0) revert Errors.InvalidDuration();

        devFeeDestination = _devFeeDestination;
        devFeePercent = _devFeePercent;
        creatorFeePercent = _creatorFeePercent;
        tradingPoolFeeDestination = _tradingPoolFeeDestination; // Can be zero before FriendPool is set up
        tradingPoolFeePercent = _tradingPoolFeePercent;
        devPerformanceFeePercent = _devPerformanceFeePercent;
        creatorPerformanceFeePercent = _creatorPerformanceFeePercent;
        bondingToken = IERC20Metadata(_bondingTokenAddress);
        friendStakeBeacon = _friendStakeBeacon;
        authority = _authority;
        eligibilityDuration = _eligibilityDuration;

        uint8 decimals = bondingToken.decimals();
        if (decimals == 0) revert Errors.InvalidDecimals();
        bondingTokenPriceUnit = 10 ** decimals;
        bondingCurveDivisors = [40, 4];
    }

    /**
     * @notice Sets the base URI for token metadata
     * @dev Only callable by contract owner
     * @param newuri The new base URI string
     */
    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function setSignee(address signee) public onlyOwner {
        if (signee == address(0)) revert Errors.ZeroAddress();
        _signee = signee;
        emit SigneeChanged(signee);
    }

    // --- Fee and Creator Management (Owner only) ---

    /**
     * @notice Sets the destination address for development fees
     * @dev Only callable by contract owner
     * @param _feeDestination New development fee destination address
     */
    function setDevFeeDestination(address _feeDestination) public onlyOwner {
        if (_feeDestination == address(0)) revert Errors.ZeroAddress();
        devFeeDestination = _feeDestination;
        emit FeeDestinationChanged(_feeDestination, Target.DevFee);
    }

    /**
     * @notice Sets the development fee percentage
     * @dev Only callable by contract owner. Must not exceed total fee limit
     * @param _feePercent New development fee percentage in basis points
     */
    function setDevFeePercent(uint256 _feePercent) public onlyOwner {
        if (_feePercent > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();
        if (_feePercent + creatorFeePercent + tradingPoolFeePercent > BPS_SCALE) {
            revert Errors.TotalFeePercentTooHigh();
        }
        devFeePercent = _feePercent;
        emit FeePercentChanged(_feePercent, Target.DevFee);
    }

    function setCreatorFeePercent(uint256 _feePercent) public onlyOwner {
        if (_feePercent > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();
        if (devFeePercent + _feePercent + tradingPoolFeePercent > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();
        creatorFeePercent = _feePercent;
        emit FeePercentChanged(_feePercent, Target.CreatorFee);
    }

    function setTradingPoolFeeDestination(address _feeDestination) public onlyOwner {
        if (_feeDestination == address(0)) revert Errors.ZeroAddress();
        tradingPoolFeeDestination = _feeDestination;
        emit FeeDestinationChanged(_feeDestination, Target.TradingPoolFee);
    }

    function setTradingPoolFeePercent(uint256 _feePercent) public onlyOwner {
        if (_feePercent > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();
        if (devFeePercent + creatorFeePercent + _feePercent > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();
        tradingPoolFeePercent = _feePercent;
        emit FeePercentChanged(_feePercent, Target.TradingPoolFee);
    }

    function setDevPerformanceFeePercent(uint256 _feePercent) public onlyOwner {
        if (creatorPerformanceFeePercent + _feePercent > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();
        devPerformanceFeePercent = _feePercent;
        emit FeePercentChanged(_feePercent, Target.DevPerformanceFee);
    }

    function setCreatorPerformanceFeePercent(uint256 _feePercent) public onlyOwner {
        if (devPerformanceFeePercent + _feePercent > BPS_SCALE) revert Errors.TotalFeePercentTooHigh();
        creatorPerformanceFeePercent = _feePercent;
        emit FeePercentChanged(_feePercent, Target.CreatorPerformanceFee);
    }

    /**
     * @notice Sets the eligibility duration for staking rewards.
     * @dev This change only affects future stake deployments; existing stakes are not affected.
     * @param _duration The new eligibility duration in seconds.
     */
    function setEligibilityDuration(uint256 _duration) public onlyOwner {
        if (_duration == 0) revert Errors.InvalidDuration();
        eligibilityDuration = _duration;
    }

    function setAuthority(address _authority) external onlyOwner {
        if (_authority == address(0)) revert Errors.ZeroAddress();
        authority = _authority;
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
        returns (uint256)
    {
        _verifyRegisterCreatorSignature(msg.sender, tier, additionalKeys, metadata, signature);
        return _registerCreator(tier, additionalKeys, metadata);
    }

    /**
     * @notice Registers a new creator with default settings (Club tier, no additional keys)
     * @dev Requires an owner signature authorizing the caller
     * @param metadata Arbitrary metadata string (e.g., IPFS hash or identifier)
     * @param signature Owner signature authorizing the registration parameters
     * @return The newly created token ID
     */
    function registerCreator(string calldata metadata, bytes calldata signature) public returns (uint256) {
        return registerCreator(RoomTier.Club, 0, metadata, signature);
    }

    function _registerCreator(RoomTier tier, uint256 additionalKeys, string calldata metadata)
        internal
        returns (uint256)
    {
        address creator = msg.sender;

        // Check if creator has already registered a room with this tier
        require(!creatorTierUsed[creator][tier], Errors.CreatorAlreadyRegistered());

        uint256 id = ++_nextTokenId;
        creatorByTokenId[id] = creator;
        roomTiers[id] = tier;

        // Mark this tier as used by the creator
        creatorTierUsed[creator][tier] = true;

        if (bytes(metadata).length > 0) {
            _metadata[id] = metadata;
        }
        string memory tokenUri = uri(id);

        bytes memory parameters = abi.encodeWithSelector(
            FriendStake.initialize.selector,
            owner(),
            address(this),
            address(bondingToken),
            id,
            authority,
            eligibilityDuration
        );
        address friendStake = address(new BeaconProxy(friendStakeBeacon, parameters));

        stakingPoolByTokenId[id] = friendStake;

        buyShares(id, 1 + additionalKeys); // Mint 1 + additional shares
        emit KeyCreated(id, creator, friendStake, tokenUri, 1 + additionalKeys, tier);

        return id;
    }

    function _verifyRegisterCreatorSignature(
        address account,
        RoomTier tier,
        uint256 additionalKeys,
        string calldata metadata,
        bytes calldata signature
    ) internal {
        uint256 nonce = registerCreatorNonces[account];
        bytes32 metadataHash = keccak256(bytes(metadata));
        bytes32 structHash = keccak256(
            abi.encode(_REGISTER_CREATOR_TYPEHASH, account, uint8(tier), additionalKeys, nonce, metadataHash)
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
    function getDivisor(uint256 id) public view returns (uint256) {
        RoomTier tier = roomTiers[id];
        return bondingCurveDivisors[uint8(tier)];
    }

    /**
     * @notice Returns the divisor for a specific room tier
     * @dev Note: updating the divisor for a tier will affect prices of all tokens with that tier
     * @param tier The room tier to get divisor for
     * @param divisor The new divisor value for the room tier
     */
    function updateDivisorByTier(RoomTier tier, uint256 divisor) public onlyOwner {
        if (divisor == 0) revert Errors.InvalidDivisor();
        bondingCurveDivisors[uint256(tier)] = divisor;
    }

    /**
     * @notice Calculates the price to buy a specific amount of tokens (before fees)
     * @param id The token ID to buy
     * @param amount Number of tokens to buy
     * @return The price in bonding token units before fees
     */
    function getBuyPrice(uint256 id, uint256 amount) public view returns (uint256) {
        uint256 divisor = bondingCurveDivisors[uint256(roomTiers[id])];
        return BondingCurveLib.getBuyPrice(totalSupply(id), amount, divisor, bondingTokenPriceUnit);
    }

    /**
     * @notice Calculates the price to sell a specific amount of tokens (before fees)
     * @param id The token ID to sell
     * @param amount Number of tokens to sell
     * @return The price in bonding token units before fees
     */
    function getSellPrice(uint256 id, uint256 amount) public view returns (uint256) {
        if (totalSupply(id) < amount) revert Errors.AmountExceedsSupply();
        uint256 divisor = bondingCurveDivisors[uint256(roomTiers[id])];
        return BondingCurveLib.getSellPrice(totalSupply(id), amount, divisor, bondingTokenPriceUnit);
    }

    /**
     * @notice Calculates the total cost to buy tokens including all fees
     * @param id The token ID to buy
     * @param amount Number of tokens to buy
     * @return The total cost including base price and all fees
     */
    function getBuyPriceAfterFee(uint256 id, uint256 amount) public view returns (uint256) {
        uint256 divisor = bondingCurveDivisors[uint256(roomTiers[id])];
        return BondingCurveLib.getBuyPriceAfterFee(
            totalSupply(id),
            amount,
            divisor,
            bondingTokenPriceUnit,
            devFeePercent,
            creatorFeePercent,
            tradingPoolFeePercent,
            BPS_SCALE
        );
    }

    /**
     * @notice Calculates the proceeds from selling tokens after deducting all fees
     * @param id The token ID to sell
     * @param amount Number of tokens to sell
     * @return The net proceeds after deducting all fees
     */
    function getSellPriceAfterFee(uint256 id, uint256 amount) public view returns (uint256) {
        uint256 divisor = bondingCurveDivisors[uint256(roomTiers[id])];
        return BondingCurveLib.getSellPriceAfterFee(
            totalSupply(id),
            amount,
            divisor,
            bondingTokenPriceUnit,
            devFeePercent,
            creatorFeePercent,
            tradingPoolFeePercent,
            BPS_SCALE
        );
    }

    // --- Buy and Sell Shares ---

    /**
     * @notice Purchases tokens for a specific creator using bonding curve pricing
     * @dev Calculates price, collects fees, mints tokens, and distributes payments
     * @param tokenId The ID of the creator's token to buy
     * @param amount Number of tokens to purchase
     */
    function buyShares(uint256 tokenId, uint256 amount) public {
        buyShares(tokenId, amount, 0);
    }

    /**
     * @notice Purchases tokens for a specific creator using bonding curve pricing with slippage protection
     * @dev Calculates price, collects fees, mints tokens, and distributes payments
     * @param tokenId The ID of the creator's token to buy
     * @param amount Number of tokens to purchase
     * @param maxSpend Maximum amount of bonding tokens to spend (0 = no limit, for backward compatibility)
     */
    function buyShares(uint256 tokenId, uint256 amount, uint256 maxSpend) public {
        if (amount == 0) revert Errors.AmountMustBeGreaterThanZero();
        address creatorAddress = creatorByTokenId[tokenId];
        if (creatorAddress == address(0)) revert Errors.CreatorNotRegistered();

        uint256 currentSupply = totalSupply(tokenId);
        if (currentSupply == 0) {
            if (msg.sender != creatorAddress) revert Errors.OnlyCreatorCanBuyFirstShare();
        }

        uint256 price = getPrice(currentSupply, amount, bondingCurveDivisors[uint256(roomTiers[tokenId])]);
        (uint256 devFee, uint256 creatorFee, uint256 tradingPoolFee) =
            BondingCurveLib.calculateFees(price, devFeePercent, creatorFeePercent, tradingPoolFeePercent, BPS_SCALE);
        uint256 totalCost = price + devFee + creatorFee + tradingPoolFee;

        // Slippage protection: ensure total cost doesn't exceed maxSpend
        if (maxSpend > 0) {
            if (totalCost > maxSpend) revert Errors.SlippageExceededMaxSpend();
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
            bool ok = bondingToken.transferFrom(msg.sender, address(this), totalCost);
            if (!ok) revert Errors.TransferFailed();
        }

        emit Trade(tokenId, msg.sender, creatorAddress, true, amount, price, currentSupply + amount);

        if (devFee > 0 && devFeeDestination != address(0)) {
            bondingToken.safeTransfer(devFeeDestination, devFee);
        }
        if (creatorFee > 0) {
            emit CreatorRewarded(tokenId, creatorAddress, creatorFee);
            bondingToken.safeTransfer(creatorAddress, creatorFee);
        }
        if (tradingPoolFee > 0 && tradingPoolFeeDestination != address(0)) {
            _transferToPool(tokenId, tradingPoolFee);
        }
    }

    /**
     * @notice Sells tokens for a specific creator using bonding curve pricing
     * @dev Burns tokens, calculates proceeds after fees, and transfers payment to seller
     * @param tokenId The ID of the creator's token to sell
     * @param amount Number of tokens to sell
     */
    function sellShares(uint256 tokenId, uint256 amount) public {
        sellShares(tokenId, amount, 0);
    }

    /**
     * @notice Sells tokens for a specific creator using bonding curve pricing with slippage protection
     * @dev Burns tokens, calculates proceeds after fees, and transfers payment to seller
     * @param tokenId The ID of the creator's token to sell
     * @param amount Number of tokens to sell
     * @param minReceive Minimum amount of bonding tokens to receive (0 = no limit, for backward compatibility)
     */
    function sellShares(uint256 tokenId, uint256 amount, uint256 minReceive) public {
        if (amount == 0) revert Errors.AmountMustBeGreaterThanZero();
        address creatorAddress = creatorByTokenId[tokenId];
        if (creatorAddress == address(0)) revert Errors.CreatorNotRegistered();
        if (balanceOf(msg.sender, tokenId) < amount) revert Errors.InsufficientShares();

        uint256 currentSupply = totalSupply(tokenId);
        if (currentSupply <= amount) revert Errors.CannotSellAllShares();

        uint256 price = getPrice(currentSupply - amount, amount, bondingCurveDivisors[uint256(roomTiers[tokenId])]);
        (uint256 devFee, uint256 creatorFee, uint256 tradingPoolFee) =
            BondingCurveLib.calculateFees(price, devFeePercent, creatorFeePercent, tradingPoolFeePercent, BPS_SCALE);

        uint256 totalFees = devFee + creatorFee + tradingPoolFee;
        uint256 proceeds = price > totalFees ? price - totalFees : 0;

        // Slippage protection: ensure proceeds meet minimum requirement
        if (minReceive > 0) {
            if (proceeds < minReceive) revert Errors.SlippageExceededMinReceive();
        }

        bondingCurveReserves[creatorAddress] -= price;
        emit Trade(tokenId, msg.sender, creatorAddress, false, amount, price, currentSupply - amount);

        _burn(msg.sender, tokenId, amount);

        if (proceeds > 0) {
            bondingToken.safeTransfer(msg.sender, proceeds);
        }
        if (devFee > 0 && devFeeDestination != address(0)) {
            bondingToken.safeTransfer(devFeeDestination, devFee);
        }
        if (creatorFee > 0) {
            emit CreatorRewarded(tokenId, creatorAddress, creatorFee);
            bondingToken.safeTransfer(creatorAddress, creatorFee);
        }
        if (tradingPoolFee > 0 && tradingPoolFeeDestination != address(0)) {
            _transferToPool(tokenId, tradingPoolFee);
        }
    }

    /**
     * @notice Stakes tokens in the associated staking pool for rewards
     * @dev Transfers tokens from user to staking pool and updates holding timestamp
     * @param tokenId The ID of the token to stake
     * @param amount Number of tokens to stake
     */
    function stake(uint256 tokenId, uint256 amount) public {
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
    function unstake(uint256 tokenId, uint256 amount) public {
        if (amount == 0) revert Errors.AmountMustBeGreaterThanZero();
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
    function _transferToPool(uint256 tokenId, uint256 tradingPoolFee) internal {
        // Check if the destination has code (is a contract)
        if (tradingPoolFeeDestination.code.length > 0) {
            // try to approve and pull from the trading pool otherwise transfer
            if (!bondingToken.approve(tradingPoolFeeDestination, tradingPoolFee)) revert Errors.ApproveFailed();
            try IFriendPool(tradingPoolFeeDestination).pull(tokenId, tradingPoolFee) {
            // If the pull succeeds, we don't need to do anything else
            }
            catch {
                bondingToken.safeTransfer(tradingPoolFeeDestination, tradingPoolFee);
            }
        } else {
            // If it's an EOA, just transfer the tokens
            bondingToken.safeTransfer(tradingPoolFeeDestination, tradingPoolFee);
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
     * @param tier The room tier to check availability for
     * @return True if the creator can still register this tier, false if already used
     */
    function canRegisterTier(address creator, RoomTier tier) public view returns (bool) {
        return !creatorTierUsed[creator][tier];
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
