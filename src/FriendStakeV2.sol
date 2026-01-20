// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    ERC1155HolderUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IterableMapping} from "./lib/IterableMapping.sol";
import {IFriendKey} from "./interfaces/IFriendKey.sol";
import {IFriendRoomManager} from "./interfaces/IFriendRoomManager.sol";
import {Errors} from "./libraries/Errors.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title FriendStake
 * @author FriendDotSpace
 * @custom:oz-upgrades-from FriendStake
 * @notice A staking contract that allows users to stake FriendKey tokens to earn rewards
 * @dev This contract manages staking pools for individual creator tokens with the following features:
 *      - Time-locked staking with configurable lock periods
 *      - Reward distribution based on staked amounts
 *      - Eligibility tracking for reward claims
 *      - Integration with FriendKey token contract
 *      - Upgradeable contract pattern
 */
contract FriendStakeV2 is Initializable, OwnableUpgradeable, ERC1155HolderUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice The FriendKey token contract that this staking pool accepts
    IFriendKey public friendKeyToken;
    /// @notice The ERC20 token used for reward distribution
    IERC20 public rewardToken;
    /// @notice The specific token ID this staking pool is for
    uint256 public tokenId;
    /// @notice Whether the staking pool is currently accepting new stakes
    bool public isOpenForStaking;
    /// @notice Number of users processed so far in current distribution round - Used to determine where to start next batch iteration
    uint256 usersProcessedThisRound;
    /// @notice Internal counter for reward eligibility calculation rounds
    uint256 calculateEligibleIndex;
    /// @notice Total amount of reward tokens available for distribution (after fees)
    uint256 public rewardAmount;
    /// @notice Time period that staked tokens are locked (in seconds)
    uint256 public lockTime;

    /// @notice Current distribution round counter
    uint256 public distributionRound;

    /// @notice Mapping to track which users have claimed rewards for each distribution round
    /// @dev Format: claimed[distributionRound][user] = true if user has claimed for this round
    mapping(uint256 => mapping(address => bool)) public claimed;

    /// @notice Total amount of tokens currently staked in this pool
    uint256 public totalStaked;
    /// @notice Total amount of tokens eligible for current reward distribution
    uint256 public totalEligible;
    /// @notice Whether the total eligible amount has been set for current distribution
    bool public isTotalEligibleSet;
    /// @notice Duration that a stake must be held to be eligible for rewards
    uint256 public eligibilityDuration;
    /// @notice Address with authority to lock staking
    address public authority;

    using IterableMapping for IterableMapping.Map;

    /// @dev Internal mapping to track staked balances and timing for each user
    IterableMapping.Map private stakedBalances;

    /// @notice Flat bridge fee (in reward token units) charged per cross-chain bridge
    /// @dev Same as FriendPool bridge fee (default $3)
    uint256 public bridgeFee;

    /// @notice Snapshot of total rewards before deducting bridge/performance fees for the current round
    uint256 public roundRewardAmount;

    /// @notice Emitted when a user stakes tokens
    /// @param user Address of the user staking tokens
    /// @param tokenId ID of the token being staked
    /// @param amount Number of tokens staked
    event KeyStaked(address indexed user, uint256 tokenId, uint256 amount);

    /// @notice Emitted when a user unstakes tokens
    /// @param user Address of the user unstaking tokens
    /// @param tokenId ID of the token being unstaked
    /// @param amount Number of tokens unstaked
    event KeyUnstaked(address indexed user, uint256 tokenId, uint256 amount);

    /// @notice Emitted when a user claims rewards
    /// @param user Address of the user claiming rewards
    /// @param tokenId ID of the token for which rewards are claimed
    /// @param totalStaked Total amount of tokens staked by the user
    /// @param netAmount Amount actually transferred to the user (after fees)
    /// @param grossAmount User’s pro-rata share before fees
    event RewardClaimed(
        address indexed user, uint256 tokenId, uint256 totalStaked, uint256 netAmount, uint256 grossAmount
    );

    /// @notice Emitted when the eligibility duration is set
    /// @param tokenId ID of the token for which eligibility duration is set
    /// @param duration Duration in seconds
    event EligibilityDurationSet(uint256 tokenId, uint256 duration);

    /// @notice Emitted when fees are distributed on lockStaking
    /// @param tokenId The staking pool tokenId
    /// @param bridgeFee Amount sent as bridge fee to dev destination
    /// @param platformShare Performance fee sent to dev destination
    /// @param creatorShare Performance fee sent to creator
    /// @param creator Address of the creator for this tokenId
    /// @param devFeeDestination Address receiving bridgeFee and platformShare
    /// @param amountBeforeFee Amount before bridge fee
    /// @param amountTotalDistributed Amount total distributed
    /// @param distributionRound Current distribution round
    /// @param totalEligible Total amount of tokens eligible for current reward distribution
    event DistributeFeeSent(
        uint256 indexed tokenId,
        uint256 bridgeFee,
        uint256 platformShare,
        uint256 creatorShare,
        address indexed creator,
        address indexed devFeeDestination,
        uint256 amountBeforeFee,
        uint256 amountTotalDistributed,
        uint256 distributionRound,
        uint256 totalEligible
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the staking pool for a specific creator token
     * @dev This function replaces the constructor in upgradeable contracts
     * @param initialOwner The address that will own this staking pool
     * @param _friendKeyAddress Address of the FriendKey token contract
     * @param _rewardToken Address of the ERC20 token used for rewards
     * @param _tokenId The specific token ID this pool will accept for staking
     * @param _authority Address with authority to lock staking
     * @param _eligibilityDuration Duration that a stake must be held to be eligible for rewards
     */
    function initialize(
        address initialOwner,
        address _friendKeyAddress,
        address _rewardToken,
        uint256 _tokenId,
        address _authority,
        uint256 _eligibilityDuration
    ) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        if (_friendKeyAddress == address(0)) revert Errors.ZeroAddress();
        if (_rewardToken == address(0)) revert Errors.ZeroAddress();
        rewardToken = IERC20(_rewardToken);
        if (!IFriendKey(_friendKeyAddress).supportsInterface(type(IERC1155).interfaceId)) {
            revert Errors.FriendKeyMustBeERC1155();
        }
        friendKeyToken = IFriendKey(_friendKeyAddress);
        tokenId = _tokenId;
        totalStaked = 0;
        totalEligible = 0;
        authority = _authority;
        isTotalEligibleSet = false;
        isOpenForStaking = true;
        eligibilityDuration = _eligibilityDuration;

        // set default bridgeFee
        bridgeFee = 3 * 10 ** IERC20Metadata(_rewardToken).decimals();
    }

    /**
     * @dev Modifier to ensure only the FriendKey contract can call certain functions
     */
    modifier onlyFriendKey() {
        if (_msgSender() != address(friendKeyToken)) revert Errors.CallerNotFriendKey();
        _;
    }

    /**
     * @dev Modifier that restricts access to either the authority address or the contract owner.
     *      Functions using this modifier can only be called by the authority or the owner.
     */
    modifier onlyAuthority() {
        if (_msgSender() != authority && _msgSender() != owner()) revert Errors.CallerNotAuthorityOrOwner();
        _;
    }

    /**
     * @dev Modifier to check if contract is paused via FriendKey -> RoomManager
     */
    modifier whenNotPaused() {
        address roomManagerAddress = friendKeyToken.roomManager();
        if (roomManagerAddress != address(0)) {
            if (IFriendRoomManager(roomManagerAddress).paused()) revert Errors.ContractPaused();
        }
        _;
    }

    /**
     * @notice Sets the duration that a stake must be held to be eligible for rewards
     * @dev Only callable by the contract owner
     * @param duration Duration in seconds
     */
    function setEligibilityDuration(uint256 duration) external onlyOwner {
        if (duration == 0) revert Errors.AmountMustBeGreaterThanZero();
        eligibilityDuration = duration;
        emit EligibilityDurationSet(tokenId, duration);
    }

    /**
     * @notice Sets the authority address that can lock staking
     * @dev Only callable by the contract owner
     * @param _authority The address to be set as authority
     */
    function setAuthority(address _authority) external onlyOwner {
        if (_authority == address(0)) revert Errors.ZeroAddress();
        authority = _authority;
    }

    /**
     * @notice Handles receipt of ERC1155 tokens for staking
     * @dev Called when tokens are transferred to this contract via safeTransferFrom
     * @param from Address that sent the tokens
     * @param id Token ID being staked
     * @param value Amount of tokens being staked
     * @param data Additional data (used to encode original sender address)
     * @return bytes4 selector indicating successful receipt
     */
    function onERC1155Received(
        address,
        /* operator */
        address from,
        uint256 id,
        uint256 value,
        bytes memory data
    )
        public
        virtual
        override
        whenNotPaused
        returns (bytes4)
    {
        if (!isOpenForStaking) revert Errors.StakingNotOpen();
        // only FriendKey tokens are allowed
        if (_msgSender() != address(friendKeyToken)) revert Errors.CallerNotFriendKey();
        if (id != tokenId) revert Errors.InvalidTokenId();
        if (value == 0) revert Errors.AmountMustBeGreaterThanZero();
        if (data.length != 0) {
            from = abi.decode(data, (address));
        }
        stakedBalances.append(from, IterableMapping.Stake(value, block.timestamp));
        // uint256 balance = stakedBalances.get(from);
        // stakedBalances.set(from, balance + value);
        totalStaked += value;
        emit KeyStaked(from, id, value);
        return this.onERC1155Received.selector;
    }
    // function to receive erc1155 tokens in batch

    function onERC1155BatchReceived(
        address, /* operator */
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public virtual override whenNotPaused returns (bytes4) {
        if (!isOpenForStaking) revert Errors.StakingNotOpen();
        if (ids.length != values.length) revert Errors.InvalidArrayLength();
        if (_msgSender() != address(friendKeyToken)) revert Errors.CallerNotFriendKey();

        if (data.length != 0) {
            from = abi.decode(data, (address));
        }

        // uint256 balance = stakedBalances.get(from);
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] != tokenId) revert Errors.InvalidTokenId();
            if (values[i] == 0) revert Errors.AmountMustBeGreaterThanZero();

            stakedBalances.append(from, IterableMapping.Stake(values[i], block.timestamp));
            // stakedBalances.set(from, balance + values[i]);
            totalStaked += values[i];
            emit KeyStaked(from, ids[i], values[i]);
        }
        return this.onERC1155BatchReceived.selector;
    }

    function _unstake(uint256 amount, address user) internal {
        if (!isOpenForStaking) revert Errors.StakingNotOpen();
        IterableMapping.Stake[] storage stakes = stakedBalances.get(user);
        uint256 remaining = amount;
        uint256 i = stakes.length;

        while (remaining > 0 && i > 0) {
            i--;
            IterableMapping.Stake storage stake = stakes[i];
            uint256 deduct = stake.amount > remaining ? remaining : stake.amount;
            stake.amount -= deduct;
            remaining -= deduct;

            // Remove stake if empty
            if (stake.amount == 0) {
                stakes.pop();
            }
        }
        if (remaining != 0) revert Errors.NotEnoughStakedBalance();

        totalStaked -= amount;
        emit KeyUnstaked(user, tokenId, amount);
        friendKeyToken.safeTransferFrom(address(this), user, tokenId, amount, "");

        // clean up empty stake list to prevent stale keys and eligibilty lookups to revert
        if (stakes.length == 0) {
            stakedBalances.remove(user);
        }
    }

    function claimRewards(address user) internal {
        if (isOpenForStaking) revert Errors.StakingStillOpen();
        if (!isTotalEligibleSet) revert Errors.TotalEligibleNotSet();
        uint256 userStake = stakedBalances.getEligibleStake(user, lockTime, eligibilityDuration);
        if (userStake == 0) revert Errors.AmountMustBeGreaterThanZero();

        uint256 remainingAmount = rewardToken.balanceOf(address(this));

        uint256 userReward = (rewardAmount * userStake) / totalEligible;
        uint256 grossBeforeFees = (roundRewardAmount * userStake) / totalEligible;
        uint256 userClaim = userReward > remainingAmount ? remainingAmount : userReward;

        if (claimed[distributionRound][user]) revert Errors.AlreadyClaimed();

        claimed[distributionRound][user] = true; // Mark user as having claimed rewards for this round

        if (userClaim > 0) {
            rewardToken.safeTransfer(user, userClaim);
        }

        emit RewardClaimed(user, tokenId, userStake, userClaim, grossBeforeFees);
    }

    function claim() external whenNotPaused {
        if (isOpenForStaking) revert Errors.StakingStillOpen();
        if (stakedBalances.getTotalStake(_msgSender()) == 0) revert Errors.AmountMustBeGreaterThanZero();
        claimRewards(_msgSender());
    }

    function unstake(uint256 amount, address user) external onlyFriendKey whenNotPaused {
        _unstake(amount, user);
    }

    function unstake(uint256 amount) external whenNotPaused {
        _unstake(amount, _msgSender());
    }

    function unstakeAll() external whenNotPaused {
        uint256 userBalance = stakedBalances.getTotalStake(_msgSender());
        _unstake(userBalance, _msgSender());
    }

    function lockStaking() public onlyAuthority {
        if (!isOpenForStaking) revert Errors.StakingAlreadyClosed();
        isOpenForStaking = false;
        lockTime = block.timestamp;
        uint256 balance = rewardToken.balanceOf(address(this));
        if (balance <= bridgeFee) revert Errors.NoRewardsToDistribute();
        // Deduct flat bridge fee and send to dev destination; remaining becomes reward pool
        (address devFeeDestination,) = friendKeyToken.getFeeDestinations();
        rewardToken.safeTransfer(devFeeDestination, bridgeFee);
        roundRewardAmount = balance;
        rewardAmount = balance - bridgeFee;
        if (rewardAmount == 0) revert Errors.NoRewardsToDistribute();

        (uint16 devPerformanceFeePercent, uint16 creatorPerformanceFeePercent) = friendKeyToken.getPerformanceFees();
        uint256 platformShare = (rewardAmount * devPerformanceFeePercent) / friendKeyToken.BPS_SCALE();
        uint256 creatorShare = (rewardAmount * creatorPerformanceFeePercent) / friendKeyToken.BPS_SCALE();

        rewardAmount -= platformShare;
        rewardToken.safeTransfer(devFeeDestination, platformShare);

        rewardAmount -= creatorShare;
        rewardToken.safeTransfer(friendKeyToken.creatorByTokenId(tokenId), creatorShare);
        emit DistributeFeeSent(
            tokenId,
            bridgeFee,
            platformShare,
            creatorShare,
            friendKeyToken.creatorByTokenId(tokenId),
            devFeeDestination,
            roundRewardAmount, // before fees
            rewardAmount, // after fees
            distributionRound,
            totalEligible
        );
        distributionRound++;
        usersProcessedThisRound = 0; // Reset for new round's processing
    }

    function calculateTotalEligible(uint256 batchSize) public {
        if (isOpenForStaking) revert Errors.StakingStillOpen();
        if (isTotalEligibleSet) revert Errors.TotalEligibleAlreadySet();
        if (batchSize == 0) revert Errors.AmountMustBeGreaterThanZero();

        uint256 startIndex = calculateEligibleIndex;
        uint256 endIndex =
            startIndex + batchSize > stakedBalances.size() ? stakedBalances.size() : startIndex + batchSize;
        for (uint256 i = startIndex; i < endIndex; i++) {
            address user = stakedBalances.getKeyAtIndex(i);
            uint256 userStake = stakedBalances.getEligibleStake(user, lockTime, eligibilityDuration);
            totalEligible += userStake;
        }
        calculateEligibleIndex = endIndex;
        if (calculateEligibleIndex == stakedBalances.size()) {
            isTotalEligibleSet = true;
        }
    }

    function distributeRewards(uint256 batchSize) public {
        if (batchSize == 0) revert Errors.AmountMustBeGreaterThanZero();
        if (isOpenForStaking) revert Errors.StakingStillOpen();
        if (!isTotalEligibleSet) {
            calculateTotalEligible(batchSize);
        }
        if (!isTotalEligibleSet) revert Errors.TotalEligibleNotSet();

        uint256 totalUsers = stakedBalances.size();
        uint256 processed = 0;
        uint256 startIndex = usersProcessedThisRound;

        for (uint256 i = startIndex; i < totalUsers && processed < batchSize; i++) {
            address user = stakedBalances.getKeyAtIndex(i);
            uint256 userStake = stakedBalances.getEligibleStake(user, lockTime, eligibilityDuration);
            if (userStake > 0 && !claimed[distributionRound][user]) {
                claimRewards(user);
                processed++;
            }
            usersProcessedThisRound++;
        }

        // If processed all users, complete distribution
        if (usersProcessedThisRound >= totalUsers) {
            isOpenForStaking = true; // Reopen staking after distribution
            isTotalEligibleSet = false;
            calculateEligibleIndex = 0;
            totalEligible = 0;
            usersProcessedThisRound = 0;
            roundRewardAmount = 0;
        }
    }

    function setBridgeFee(uint256 newFee) external onlyOwner {
        if (newFee == 0) revert Errors.AmountMustBeGreaterThanZero();
        bridgeFee = newFee;
    }

    /**
     * @dev Authorizes contract upgrades - only callable by owner
     * @param _newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
