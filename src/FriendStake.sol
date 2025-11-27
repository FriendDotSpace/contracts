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

/**
 * @title FriendStake
 * @author FriendDotSpace
 * @notice A staking contract that allows users to stake FriendKey tokens to earn rewards
 * @dev This contract manages staking pools for individual creator tokens with the following features:
 *      - Time-locked staking with configurable lock periods
 *      - Reward distribution based on staked amounts
 *      - Eligibility tracking for reward claims
 *      - Integration with FriendKey token contract
 *      - Upgradeable contract pattern
 */
contract FriendStake is Initializable, OwnableUpgradeable, ERC1155HolderUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice The FriendKey token contract that this staking pool accepts
    IFriendKey public friendKeyToken;
    /// @notice The ERC20 token used for reward distribution
    IERC20 public rewardToken;
    /// @notice The specific token ID this staking pool is for
    uint256 public tokenId;
    /// @notice Whether the staking pool is currently accepting new stakes
    bool public isOpenForStaking;
    /// @dev Internal counter for reward distribution rounds
    uint256 rewardDistributionIndex;
    /// @dev Internal counter for reward eligibility calculation rounds
    uint256 calculateEligibleIndex;
    /// @notice Total amount of reward tokens available for distribution
    uint256 public rewardAmount;
    /// @notice Time period that staked tokens are locked (in seconds)
    uint256 public lockTime;

    /// @notice Array to track which users have claimed rewards for current distribution
    /// @dev Using array instead of mapping for gas-efficient reset after distribution.
    ///      The array is reset for each new distribution round in the `resetClaims()` function.
    bool[] public claimed;

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
    /// @param amount Amount of reward tokens claimed
    event RewardClaimed(address indexed user, uint256 tokenId, uint256 amount);

    /// @notice Emitted when the eligibility duration is set
    /// @param tokenId ID of the token for which eligibility duration is set
    /// @param duration Duration in seconds
    event EligibilityDurationSet(uint256 tokenId, uint256 duration);

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
        // __UUPSUpgradeable_init();
        require(_friendKeyAddress != address(0), "FriendKey address cannot be zero");
        require(_rewardToken != address(0), "Reward token address cannot be zero");
        rewardToken = IERC20(_rewardToken);
        require(
            IFriendKey(_friendKeyAddress).supportsInterface(type(IERC1155).interfaceId),
            "FriendKey address must be an ERC1155 contract"
        );
        friendKeyToken = IFriendKey(_friendKeyAddress);
        tokenId = _tokenId;
        totalStaked = 0;
        totalEligible = 0;
        authority = _authority;
        isTotalEligibleSet = false;
        isOpenForStaking = true;
        eligibilityDuration = _eligibilityDuration;
    }

    /**
     * @dev Modifier to ensure only the FriendKey contract can call certain functions
     */
    modifier onlyFriendKey() {
        require(_msgSender() == address(friendKeyToken), "FriendStake: Caller is not FriendKey contract");
        _;
    }

    /**
     * @dev Modifier that restricts access to either the authority address or the contract owner.
     *      Functions using this modifier can only be called by the authority or the owner.
     */
    modifier onlyAuthority() {
        require(_msgSender() == authority || _msgSender() == owner(), "FriendStake: Caller is not authority or owner");
        _;
    }

    /**
     * @notice Sets the duration that a stake must be held to be eligible for rewards
     * @dev Only callable by the contract owner
     * @param duration Duration in seconds
     */
    function setEligibilityDuration(uint256 duration) external onlyOwner {
        require(duration > 0, "Eligibility duration must be positive");
        eligibilityDuration = duration;
        emit EligibilityDurationSet(tokenId, duration);
    }

    /**
     * @notice Sets the authority address that can lock staking
     * @dev Only callable by the contract owner
     * @param _authority The address to be set as authority
     */
    function setAuthority(address _authority) external onlyOwner {
        require(_authority != address(0), "Authority address cannot be zero");
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
        returns (bytes4)
    {
        require(isOpenForStaking, "FriendStake: Staking is not open");
        // only FriendKey tokens are allowed
        require(_msgSender() == address(friendKeyToken), "FriendStake: Only FriendKey tokens can be staked");
        require(id == tokenId, "FriendStake: Invalid token ID");
        require(value > 0, "FriendStake: Cannot stake zero tokens");
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
        bytes memory /* data */
    )
        public
        virtual
        override
        returns (bytes4)
    {
        require(isOpenForStaking, "FriendStake: Staking is not open");
        require(ids.length == values.length, "FriendStake: IDs and values length mismatch");
        require(_msgSender() == address(friendKeyToken), "FriendStake: Only FriendKey tokens can be staked");

        // uint256 balance = stakedBalances.get(from);
        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] == tokenId, "FriendStake: Invalid token ID");
            require(values[i] > 0, "FriendStake: Cannot stake zero tokens");

            stakedBalances.append(from, IterableMapping.Stake(values[i], block.timestamp));
            // stakedBalances.set(from, balance + values[i]);
            totalStaked += values[i];
            emit KeyStaked(from, ids[i], values[i]);
        }
        return this.onERC1155BatchReceived.selector;
    }

    function _unstake(uint256 amount, address user) internal {
        require(isOpenForStaking, "FriendStake: Reward distribution in progress");
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
        require(remaining == 0, "Not enough staked balance");

        totalStaked -= amount;
        emit KeyUnstaked(user, tokenId, amount);
        friendKeyToken.safeTransferFrom(address(this), user, tokenId, amount, "");
    }

    function claimRewards(address user) internal {
        require(!isOpenForStaking, "FriendStake: Staking is still open");
        require(isTotalEligibleSet, "FriendStake: Total staked amount is not set");
        uint256 userStake = stakedBalances.getEligibleStake(user, lockTime, eligibilityDuration);
        require(userStake > 0, "FriendStake: No staked tokens to claim rewards");

        uint256 remainingAmount = rewardToken.balanceOf(address(this));

        uint256 userReward = (rewardAmount * userStake) / totalEligible;
        uint256 userClaim = userReward > remainingAmount ? remainingAmount : userReward;

        uint256 userIndex = stakedBalances.getIndexOfKey(user);
        require(!claimed[userIndex], "FriendStake: User has already claimed rewards");

        claimed[userIndex] = true; // Mark user as having claimed rewards

        if (userClaim > 0) {
            rewardToken.safeTransfer(user, userClaim);
        }

        emit RewardClaimed(user, tokenId, userClaim);
    }

    function claim() external {
        require(!isOpenForStaking, "FriendStake: Staking is still open");
        require(stakedBalances.getTotalStake(_msgSender()) > 0, "FriendStake: No staked tokens to claim rewards");
        claimRewards(_msgSender());
    }

    function unstake(uint256 amount, address user) external onlyFriendKey {
        _unstake(amount, user);
    }

    function unstake(uint256 amount) external {
        _unstake(amount, _msgSender());
    }

    function unstakeAll() external {
        uint256 userBalance = stakedBalances.getTotalStake(_msgSender());
        _unstake(userBalance, _msgSender());
    }

    function lockStaking() public onlyAuthority {
        require(isOpenForStaking, "FriendStake: Staking is already closed");
        isOpenForStaking = false;
        lockTime = block.timestamp;
        rewardAmount = rewardToken.balanceOf(address(this));
        require(rewardAmount > 0, "FriendStake: No rewards to distribute");

        (uint16 devPerformanceFeePercent, uint16 creatorPerformanceFeePercent) = friendKeyToken.getPerformanceFees();
        uint256 platformShare = (rewardAmount * devPerformanceFeePercent) / friendKeyToken.BPS_SCALE();
        uint256 creatorShare =
            (rewardAmount * creatorPerformanceFeePercent) / friendKeyToken.BPS_SCALE();

        rewardAmount -= platformShare;
        (address devFeeDestination, address poolFeeDestination) = friendKeyToken.getFeeDestinations();
        rewardToken.safeTransfer(devFeeDestination, platformShare);
        emit RewardClaimed(devFeeDestination, tokenId, platformShare);

        rewardAmount -= creatorShare;
        rewardToken.safeTransfer(friendKeyToken.creatorByTokenId(tokenId), creatorShare);
        emit RewardClaimed(friendKeyToken.creatorByTokenId(tokenId), tokenId, creatorShare);

        claimed = new bool[](stakedBalances.size()); // Reset claimed array
    }

    function calculateTotalEligible(uint256 batchSize) public {
        require(!isOpenForStaking, "FriendStake: Staking is still open");
        require(!isTotalEligibleSet, "FriendStake: Total staked amount is already set");
        require(batchSize > 0, "FriendStake: Batch size must be greater than zero");

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
        require(batchSize > 0, "FriendStake: Batch size must be greater than zero");
        require(!isOpenForStaking, "FriendStake: Staking is still open");
        if (!isTotalEligibleSet) {
            calculateTotalEligible(batchSize);
        }
        require(isTotalEligibleSet, "FriendStake: Total staked amount is not set");
        uint256 endIndex = rewardDistributionIndex + batchSize > stakedBalances.size()
            ? stakedBalances.size()
            : rewardDistributionIndex + batchSize;
        for (; rewardDistributionIndex < endIndex; rewardDistributionIndex++) {
            address user = stakedBalances.getKeyAtIndex(rewardDistributionIndex);
            uint256 userStake = stakedBalances.getEligibleStake(user, lockTime, eligibilityDuration);
            if (userStake > 0 && !claimed[rewardDistributionIndex]) {
                claimRewards(user);
            }
        }
        if (rewardDistributionIndex == stakedBalances.size()) {
            isOpenForStaking = true; // Reopen staking after distribution
            isTotalEligibleSet = false;
            calculateEligibleIndex = 0;
            totalEligible = 0;
        }
    }

    /**
     * @dev Authorizes contract upgrades - only callable by owner
     * @param _newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
