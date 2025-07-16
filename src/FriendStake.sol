// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC1155HolderUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IterableMapping} from "./lib/IterableMapping.sol";

contract FriendStake is Initializable, OwnableUpgradeable, ERC1155HolderUpgradeable {
    using SafeERC20 for IERC20;

    IERC1155 public friendKeyToken;
    IERC20 public rewardToken;
    uint256 public tokenId;
    bool public isOpenForStaking;
    uint256 rewardDistributionIndex;
    uint256 public rewardAmount;

    // Array to track users who have claimed rewards
    // We use array instead of mapping for ability to reset to empty
    // after reward distribution
    bool[] public claimed;

    uint256 public totalStaked;

    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private stakedBalances;

    event KeyStaked(address indexed user, uint256 tokenId, uint256 amount);
    event KeyUnstaked(address indexed user, uint256 tokenId, uint256 amount);
    event RewardClaimed(address indexed user, uint256 tokenId, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _friendKeyAddress, address _rewardToken, uint256 _tokenId)
        public
        initializer
    {
        __Ownable_init(initialOwner);
        // __UUPSUpgradeable_init();
        require(_friendKeyAddress != address(0), "FriendKey address cannot be zero");
        require(_rewardToken != address(0), "Reward token address cannot be zero");
        rewardToken = IERC20(_rewardToken);
        require(
            IERC1155(_friendKeyAddress).supportsInterface(type(IERC1155).interfaceId),
            "FriendKey address must be an ERC1155 contract"
        );
        friendKeyToken = IERC1155(_friendKeyAddress);
        tokenId = _tokenId;
        totalStaked = 0;
        isOpenForStaking = true;
    }

    // function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // function to receive erc1155 tokens
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes memory data)
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
        uint256 balance = stakedBalances.get(from);
        stakedBalances.set(from, balance + value);
        totalStaked += value;
        emit KeyStaked(from, id, value);
        return this.onERC1155Received.selector;
    }
    // function to receive erc1155 tokens in batch

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public virtual override returns (bytes4) {
        require(isOpenForStaking, "FriendStake: Staking is not open");
        require(ids.length == values.length, "FriendStake: IDs and values length mismatch");
        require(_msgSender() == address(friendKeyToken), "FriendStake: Only FriendKey tokens can be staked");

        uint256 balance = stakedBalances.get(from);
        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] == tokenId, "FriendStake: Invalid token ID");
            require(values[i] > 0, "FriendStake: Cannot stake zero tokens");

            stakedBalances.set(from, balance + values[i]);
            totalStaked += values[i];
            emit KeyStaked(from, ids[i], values[i]);
        }
        return this.onERC1155BatchReceived.selector;
    }

    function unstake(uint256 amount, address user) internal {
        require(isOpenForStaking, "FriendStake: Reward distribution in progress");
        require(stakedBalances.get(user) >= amount, "FriendStake: Insufficient staked balance");
        uint256 balance = stakedBalances.get(user);
        if (balance - amount == 0) {
            stakedBalances.remove(user);
        } else {
            stakedBalances.set(user, balance - amount);
        }
        totalStaked -= amount;
        friendKeyToken.safeTransferFrom(address(this), user, tokenId, amount, "");
        emit KeyUnstaked(user, tokenId, amount);
    }

    function claimRewards(address user) internal {
        require(!isOpenForStaking, "FriendStake: Staking is still open");
        uint256 userStake = stakedBalances.get(user);
        require(userStake > 0, "FriendStake: No staked tokens to claim rewards");

        uint256 remainingAmount = rewardToken.balanceOf(address(this));

        uint256 userReward = (rewardAmount * userStake) / totalStaked;
        uint256 userClaim = userReward > remainingAmount ? remainingAmount : userReward;

        require(userClaim > 0, "FriendStake: No reward for user");
        uint256 userIndex = stakedBalances.getIndexOfKey(user);
        require(!claimed[userIndex], "FriendStake: User has already claimed rewards");

        claimed[userIndex] = true; // Mark user as having claimed rewards

        rewardToken.safeTransfer(user, userClaim);

        emit RewardClaimed(user, tokenId, userClaim);
    }

    function claim() external {
        require(!isOpenForStaking, "FriendStake: Staking is still open");
        require(stakedBalances.get(_msgSender()) > 0, "FriendStake: No staked tokens to claim rewards");
        claimRewards(_msgSender());
    }

    function unstake(uint256 amount) external {
        unstake(amount, _msgSender());
    }

    function unstakeAll() external {
        uint256 userBalance = stakedBalances.get(_msgSender());
        unstake(userBalance, _msgSender());
    }

    function lockStaking() public onlyOwner {
        require(isOpenForStaking, "FriendStake: Staking is already closed");
        isOpenForStaking = false;
        rewardAmount = rewardToken.balanceOf(address(this));
        rewardDistributionIndex = 0;

        claimed = new bool[](stakedBalances.size()); // Reset claimed array
    }

    function distributeRewards(uint256 batchSize) public {
        require(!isOpenForStaking, "FriendStake: Staking is still open");

        uint256 endIndex = rewardDistributionIndex + batchSize > stakedBalances.size()
            ? stakedBalances.size()
            : rewardDistributionIndex + batchSize;
        for (; rewardDistributionIndex < endIndex; rewardDistributionIndex++) {
            address user = stakedBalances.getKeyAtIndex(rewardDistributionIndex);
            uint256 userStake = stakedBalances.get(user);
            if (userStake > 0 && !claimed[rewardDistributionIndex]) {
                claimRewards(user);
            }
        }
        if (rewardDistributionIndex == stakedBalances.size()) {
            isOpenForStaking = true; // Reopen staking after distribution
        }
    }
}
