// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IFriendPool} from "./interfaces/IFriendPool.sol";
import {FriendStake} from "./FriendStake.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title FriendKey
 * @author FriendDotSpace
 * @notice A social token platform that allows creators to issue their own tokenized shares using bonding curves
 * @dev This contract implements an ERC-1155 based social token system with the following features:
 *      - Bonding curve pricing mechanism for token purchases/sales
 *      - Multi-tier room system (Casual, Club, Exclusive) with different pricing curves
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
    UUPSUpgradeable
{
    using SafeERC20 for IERC20Metadata;
    using Strings for uint256;

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
    /// @notice Address of the FriendStake implementation contract for cloning
    address public friendStake;

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

    /// @notice Array of divisors for different room tiers [Casual, Club, Exclusive]
    /// @dev Lower divisor = higher prices. Used in bonding curve calculations
    uint256[] public bondingCurveDivisors;

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
    event KeyStaked(uint256 indexed tokenId, address indexed staker, uint256 amount);

    /// @notice Emitted when tokens are unstaked
    /// @param tokenId The ID of the token being unstaked
    /// @param staker The address unstaking the tokens
    /// @param amount The amount of tokens unstaked
    event KeyUnstaked(uint256 indexed tokenId, address indexed staker, uint256 amount);
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
     * @param _friendStake Address of the FriendStake implementation for cloning
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
        address _friendStake
    ) public initializer {
        __ERC1155_init("");
        __Ownable_init(initialOwner);
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __UUPSUpgradeable_init();

        BPS_SCALE = 10000;

        require(_devFeePercent + _creatorFeePercent + _tradingPoolFeePercent <= BPS_SCALE, "Total fee percent too high");
        require(_bondingTokenAddress != address(0), "Bonding token address cannot be zero");
        require(_devFeeDestination != address(0), "Dev fee destination cannot be zero");
        require(_friendStake != address(0), "FriendStake address cannot be zero");

        devFeeDestination = _devFeeDestination;
        devFeePercent = _devFeePercent;
        creatorFeePercent = _creatorFeePercent;
        tradingPoolFeeDestination = _tradingPoolFeeDestination; // Can be zero before FriendPool is set up
        tradingPoolFeePercent = _tradingPoolFeePercent;
        devPerformanceFeePercent = _devPerformanceFeePercent;
        creatorPerformanceFeePercent = _creatorPerformanceFeePercent;
        bondingToken = IERC20Metadata(_bondingTokenAddress);
        friendStake = _friendStake;

        uint8 decimals = bondingToken.decimals();
        require(decimals > 0, "Bonding token decimals must be greater than zero");
        bondingTokenPriceUnit = 10 ** decimals;
        bondingCurveDivisors = [4000, 40, 4];
    }

    /**
     * @notice Sets the base URI for token metadata
     * @dev Only callable by contract owner
     * @param newuri The new base URI string
     */
    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    // --- Fee and Creator Management (Owner only) ---

    /**
     * @notice Sets the destination address for development fees
     * @dev Only callable by contract owner
     * @param _feeDestination New development fee destination address
     */
    function setDevFeeDestination(address _feeDestination) public onlyOwner {
        require(_feeDestination != address(0), "Dev fee destination cannot be zero");
        devFeeDestination = _feeDestination;
        emit FeeDestinationChanged(_feeDestination, Target.DevFee);
    }

    /**
     * @notice Sets the development fee percentage
     * @dev Only callable by contract owner. Must not exceed total fee limit
     * @param _feePercent New development fee percentage in basis points
     */
    function setDevFeePercent(uint256 _feePercent) public onlyOwner {
        require(_feePercent <= BPS_SCALE, "Dev fee percent too high");
        require(_feePercent + creatorFeePercent + tradingPoolFeePercent <= BPS_SCALE, "Total fee percent too high");
        devFeePercent = _feePercent;
        emit FeePercentChanged(_feePercent, Target.DevFee);
    }

    function setCreatorFeePercent(uint256 _feePercent) public onlyOwner {
        require(_feePercent <= BPS_SCALE, "Creator fee percent too high");
        require(devFeePercent + _feePercent + tradingPoolFeePercent <= BPS_SCALE, "Total fee percent too high");
        creatorFeePercent = _feePercent;
        emit FeePercentChanged(_feePercent, Target.CreatorFee);
    }

    function setTradingPoolFeeDestination(address _feeDestination) public onlyOwner {
        require(_feeDestination != address(0), "Trading pool fee destination cannot be zero");
        tradingPoolFeeDestination = _feeDestination;
        emit FeeDestinationChanged(_feeDestination, Target.TradingPoolFee);
    }

    function setTradingPoolFeePercent(uint256 _feePercent) public onlyOwner {
        require(_feePercent <= BPS_SCALE, "Trading pool fee percent too high");
        require(devFeePercent + creatorFeePercent + _feePercent <= BPS_SCALE, "Total fee percent too high");
        tradingPoolFeePercent = _feePercent;
        emit FeePercentChanged(_feePercent, Target.TradingPoolFee);
    }

    function setDevPerformanceFeePercent(uint256 _feePercent) public onlyOwner {
        require(creatorPerformanceFeePercent + _feePercent <= BPS_SCALE, "Dev performance fee percent too high");
        devPerformanceFeePercent = _feePercent;
        emit FeePercentChanged(_feePercent, Target.DevPerformanceFee);
    }

    function setCreatorPerformanceFeePercent(uint256 _feePercent) public onlyOwner {
        require(devPerformanceFeePercent + _feePercent <= BPS_SCALE, "Creator performance fee percent too high");
        creatorPerformanceFeePercent = _feePercent;
        emit FeePercentChanged(_feePercent, Target.CreatorPerformanceFee);
    }

    /**
     * @notice Registers a new creator with specified tier and additional keys
     * @dev Creates a new token ID, deploys a staking pool, and mints initial supply
     * @param tier The room tier for the creator (affects bonding curve pricing)
     * @param additionalKeys Number of additional keys to mint beyond the initial key
     * @return The newly created token ID
     */
    function registerCreator(RoomTier tier, uint256 additionalKeys) public returns (uint256) {
        address creator = msg.sender;
        uint256 id = ++_nextTokenId;
        creatorByTokenId[id] = creator;
        roomTiers[id] = tier;
        string memory tokenUri = uri(id);

        address cloneAddress = Clones.clone(friendStake);
        stakingPoolByTokenId[id] = cloneAddress;
        FriendStake(cloneAddress).initialize(owner(), address(this), address(bondingToken), id);

        buyShares(id, 1 + additionalKeys); // Mint 1 + additional shares
        emit KeyCreated(id, creator, cloneAddress, tokenUri, 1 + additionalKeys, tier);

        return id;
    }

    /**
     * @notice Registers a new creator with default settings (Casual tier, no additional keys)
     * @dev Backward-compatible function that uses default parameters
     * @return The newly created token ID
     */
    function registerCreator() public returns (uint256) {
        return registerCreator(RoomTier.Casual, 0);
    }

    /**
     * @notice Returns the metadata URI for a specific token
     * @dev Concatenates base URI with token ID if base URI is set
     * @param tokenId The token ID to get URI for
     * @return The complete metadata URI for the token
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        address creator = creatorByTokenId[tokenId];
        require(creator != address(0), "Creator not registered");
        string memory tokenURI = tokenId.toString();
        string memory base = super.uri(tokenId);

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
        require(divisor > 0, "Divisor must be greater than zero");
        uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : ((supply + amount - 1) * (supply + amount) * (2 * (supply + amount - 1) + 1)) / 6;
        uint256 summation = sum2 - sum1;
        return (summation * bondingTokenPriceUnit) / divisor;
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
     * @notice Calculates the price to buy a specific amount of tokens (before fees)
     * @param id The token ID to buy
     * @param amount Number of tokens to buy
     * @return The price in bonding token units before fees
     */
    function getBuyPrice(uint256 id, uint256 amount) public view returns (uint256) {
        uint256 divisor = bondingCurveDivisors[uint256(roomTiers[id])];
        return getPrice(totalSupply(id), amount, divisor);
    }

    /**
     * @notice Calculates the price to sell a specific amount of tokens (before fees)
     * @param id The token ID to sell
     * @param amount Number of tokens to sell
     * @return The price in bonding token units before fees
     */
    function getSellPrice(uint256 id, uint256 amount) public view returns (uint256) {
        require(totalSupply(id) >= amount, "Amount exceeds supply");
        uint256 divisor = bondingCurveDivisors[uint256(roomTiers[id])];
        return getPrice(totalSupply(id) - amount, amount, divisor);
    }

    /**
     * @notice Calculates the total cost to buy tokens including all fees
     * @param id The token ID to buy
     * @param amount Number of tokens to buy
     * @return The total cost including base price and all fees
     */
    function getBuyPriceAfterFee(uint256 id, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(id, amount);
        uint256 devFee = (price * devFeePercent) / BPS_SCALE;
        uint256 creatorFee = (price * creatorFeePercent) / BPS_SCALE;
        uint256 tradingPoolFee = (price * tradingPoolFeePercent) / BPS_SCALE;
        return price + devFee + creatorFee + tradingPoolFee;
    }

    /**
     * @notice Calculates the proceeds from selling tokens after deducting all fees
     * @param id The token ID to sell
     * @param amount Number of tokens to sell
     * @return The net proceeds after deducting all fees
     */
    function getSellPriceAfterFee(uint256 id, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(id, amount);
        uint256 devFee = (price * devFeePercent) / BPS_SCALE;
        uint256 creatorFee = (price * creatorFeePercent) / BPS_SCALE;
        uint256 tradingPoolFee = (price * tradingPoolFeePercent) / BPS_SCALE;
        uint256 totalFees = devFee + creatorFee + tradingPoolFee;
        return price > totalFees ? price - totalFees : 0;
    }

    // --- Buy and Sell Shares ---

    /**
     * @notice Purchases tokens for a specific creator using bonding curve pricing
     * @dev Calculates price, collects fees, mints tokens, and distributes payments
     * @param tokenId The ID of the creator's token to buy
     * @param amount Number of tokens to purchase
     */
    function buyShares(uint256 tokenId, uint256 amount) public {
        require(amount > 0, "Amount must be greater than zero");
        address creatorAddress = creatorByTokenId[tokenId];
        require(creatorAddress != address(0), "Creator not registered or no token ID associated");

        uint256 currentSupply = totalSupply(tokenId);
        if (currentSupply == 0) {
            require(msg.sender == creatorAddress, "Only creator can buy the first share");
        }

        uint256 price = getPrice(currentSupply, amount, bondingCurveDivisors[uint256(roomTiers[tokenId])]);
        uint256 devFee = (price * devFeePercent) / BPS_SCALE;
        uint256 creatorFee = (price * creatorFeePercent) / BPS_SCALE;
        uint256 tradingPoolFee = (price * tradingPoolFeePercent) / BPS_SCALE;
        uint256 totalCost = price + devFee + creatorFee + tradingPoolFee;

        bondingCurveReserves[creatorAddress] += price;

        _mint(msg.sender, tokenId, amount, "");

        if (totalCost > 0) {
            // Check the allowance and balance first
            uint256 allowance = bondingToken.allowance(msg.sender, address(this));
            require(allowance >= totalCost, "Insufficient allowance for bonding token transfer");
            uint256 balance = bondingToken.balanceOf(msg.sender);
            require(balance >= totalCost, "Insufficient bonding token balance");
            // Transfer the bonding token from the user to this contract
            bool ok = bondingToken.transferFrom(msg.sender, address(this), totalCost);
            require(ok, "Transfer failed");
        }

        // FriendStake stakingPool = FriendStake(stakingPoolByTokenId[tokenId]);
        // if (stakingPool.isOpenForStaking() == false) {
        //     _mint(msg.sender, tokenId, amount, "");
        // } else {
        //     bytes memory sender = abi.encode(msg.sender);
        //     _mint(stakingPoolByTokenId[tokenId], tokenId, amount, sender);
        // }
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
        require(amount > 0, "Amount must be greater than zero");
        address creatorAddress = creatorByTokenId[tokenId];
        require(creatorAddress != address(0), "Creator not registered or no token ID associated");
        require(balanceOf(msg.sender, tokenId) >= amount, "Insufficient shares");

        uint256 currentSupply = totalSupply(tokenId);
        require(currentSupply > amount, "Cannot sell shares if it makes supply zero or less through this method");

        uint256 price = getPrice(currentSupply - amount, amount, bondingCurveDivisors[uint256(roomTiers[tokenId])]);
        uint256 devFee = (price * devFeePercent) / BPS_SCALE;
        uint256 creatorFee = (price * creatorFeePercent) / BPS_SCALE;
        uint256 tradingPoolFee = (price * tradingPoolFeePercent) / BPS_SCALE;

        uint256 totalFees = devFee + creatorFee + tradingPoolFee;
        uint256 proceeds = price > totalFees ? price - totalFees : 0;

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
        require(amount > 0, "Amount must be greater than zero");
        require(balanceOf(msg.sender, tokenId) >= amount, "Insufficient shares to stake");
        address stakingPoolAddress = stakingPoolByTokenId[tokenId];
        require(stakingPoolAddress != address(0), "Staking pool not registered for this token ID");
        emit KeyStaked(tokenId, msg.sender, amount);

        FriendStake stakingPool = FriendStake(stakingPoolAddress);
        require(stakingPool.isOpenForStaking(), "Staking pool is not open for staking");

        _safeTransferFrom(msg.sender, stakingPoolAddress, tokenId, amount, "");
    }

    /**
     * @notice Unstakes tokens from the staking pool
     * @dev Calls the staking pool to transfer tokens back to user
     * @param tokenId The ID of the token to unstake
     * @param amount Number of tokens to unstake
     */
    function unstake(uint256 tokenId, uint256 amount) public {
        require(amount > 0, "Amount must be greater than zero");
        address stakingPoolAddress = stakingPoolByTokenId[tokenId];
        require(stakingPoolAddress != address(0), "Staking pool not registered for this token ID");

        FriendStake stakingPool = FriendStake(stakingPoolAddress);
        require(stakingPool.isOpenForStaking(), "Staking pool is not open for unstaking");

        emit KeyUnstaked(tokenId, msg.sender, amount);

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
            require(bondingToken.approve(tradingPoolFeeDestination, tradingPoolFee), "Approve to trading pool failed");
            try IFriendPool(tradingPoolFeeDestination).pull(tokenId, tradingPoolFee) {
                // If the pull succeeds, we don't need to do anything else
            } catch {
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
        require(holdingSince > 0, "User does not hold this token");
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
        // Call super first to get the updated balances when checking in the later conditions
        super._update(from, to, ids, values);

        // For each token ID in the batch
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];

            // Handle recipient (to) - for mint and transfer operations
            if (to != address(0) && balanceOf(to, tokenId) == values[i]) {
                keyHoldingSince[tokenId][to] = block.timestamp;
            }

            // Handle sender (from) - reset timestamp if they no longer hold the token
            if (from != address(0) && balanceOf(from, tokenId) == 0) {
                keyHoldingSince[tokenId][from] = 0;
            }
        }
    }
}
