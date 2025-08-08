// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendStake} from "src/FriendStake.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

// Use the same MockERC20 from FriendKey.t.sol
import {MockERC20} from "./FriendKey.t.sol";

contract FriendStakeTest is Test {
    FriendKey public friendKey;
    FriendStake public stake;
    MockERC20 public mockUsdc;

    address public owner;
    address public devFeeDestination;
    address public tradingPoolFeeDestination;
    address public creatorAccount;
    address public staker1;
    address public staker2;

    uint256 public constant DEV_FEE_PERCENT = 100;
    uint256 public constant CREATOR_FEE_PERCENT = 100;
    uint256 public constant TRADING_POOL_FEE_PERCENT = 100;
    uint256 public constant DEV_PERFORMANCE_FEE_PERCENT = 500;
    uint256 public constant CREATOR_PERFORMANCE_FEE_PERCENT = 1500;
    uint256 public CREATOR_TOKEN_ID = 1;

    function setUp() public {
        owner = vm.addr(1);
        devFeeDestination = vm.addr(2);
        tradingPoolFeeDestination = vm.addr(4);
        creatorAccount = vm.addr(5);
        staker1 = vm.addr(6);
        staker2 = vm.addr(7);

        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);

        FriendStake friendStake = new FriendStake();

        // Deploy FriendKey
        vm.startPrank(owner);
        bytes memory initializeData = abi.encodeCall(
            FriendKey.initialize,
            (
                owner,
                devFeeDestination,
                DEV_FEE_PERCENT,
                CREATOR_FEE_PERCENT,
                tradingPoolFeeDestination,
                TRADING_POOL_FEE_PERCENT,
                DEV_PERFORMANCE_FEE_PERCENT,
                CREATOR_PERFORMANCE_FEE_PERCENT,
                address(mockUsdc),
                address(friendStake)
            )
        );
        address proxy = Upgrades.deployUUPSProxy("FriendKey.sol", initializeData);
        friendKey = FriendKey(proxy);
        vm.stopPrank();

        // Register creator and mint initial share
        vm.startPrank(creatorAccount);
        friendKey.registerCreator();
        stake = FriendStake(friendKey.stakingPoolByTokenId(CREATOR_TOKEN_ID));
        vm.stopPrank();

        // Mint tokens to stakers
        mockUsdc.mint(creatorAccount, 1_000_000 * (10 ** 6));
        mockUsdc.mint(staker1, 1_000_000 * (10 ** 6));
        mockUsdc.mint(staker2, 1_000_000 * (10 ** 6));
    }

    function testStakeSingleShare() public {
        // Creator buys another share to stake
        vm.startPrank(creatorAccount);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 1);

        friendKey.stake(CREATOR_TOKEN_ID, 2); // Stake the initial share + the one just bought

        // Check staked balance 1 initial + 1 bought
        assertEq(stake.totalStaked(), 2);
        vm.stopPrank();
    }

    function testStakeBatch() public {
        // Staker1 buys 3 shares
        vm.startPrank(staker1);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 3);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 3);

        stake.unstake(2); // Unstake 2 share to test batch staking
        assertEq(stake.totalStaked(), 2);

        // Approve and stake 2 shares in batch
        friendKey.setApprovalForAll(address(stake), true);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = CREATOR_TOKEN_ID;
        amounts[0] = 2;
        friendKey.safeBatchTransferFrom(staker1, address(stake), ids, amounts, "");

        assertEq(stake.totalStaked(), 4);
        vm.stopPrank();
    }

    function testUnstake() public {
        // Staker1 buys and stakes
        vm.startPrank(staker1);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 2);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 2);
        friendKey.stake(CREATOR_TOKEN_ID, 2);
        assertEq(stake.totalStaked(), 2); // 1 initial + 2 staked

        // Unstake 1
        stake.unstake(1);
        assertEq(stake.totalStaked(), 1);
        // Unstake remaining
        stake.unstakeAll();
        assertEq(stake.totalStaked(), 0); // 1 initial share by owner remains staked
        vm.stopPrank();
    }

    function testDistributeRewards() public {
        // Staker1 and Staker2 buy and stake
        vm.startPrank(staker1);
        uint256 price1 = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 2);
        mockUsdc.approve(address(friendKey), price1);
        friendKey.buyShares(CREATOR_TOKEN_ID, 2);
        friendKey.stake(CREATOR_TOKEN_ID, 2);
        vm.stopPrank();

        vm.startPrank(staker2);
        uint256 price2 = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 3);
        mockUsdc.approve(address(friendKey), price2);
        friendKey.buyShares(CREATOR_TOKEN_ID, 3);
        friendKey.stake(CREATOR_TOKEN_ID, 3);
        vm.stopPrank();

        // Fund rewards
        uint256 rewardAmount = 1_000 * (10 ** 6);
        mockUsdc.mint(address(stake), rewardAmount);

        // Owner closes staking
        vm.prank(owner);
        vm.warp(block.timestamp + 1 days); // Ensure enough time has passed for rewards to be eligible

        stake.lockStaking();
        assertEq(stake.isOpenForStaking(), false);
        uint256 expectedStaked = 5;
        assertEq(stake.totalStaked(), expectedStaked); // 2 from staker1 + 3 from staker2
        vm.stopPrank();

        // Check initial balances
        uint256 staker1InitialBalance = mockUsdc.balanceOf(staker1);
        uint256 staker2InitialBalance = mockUsdc.balanceOf(staker2);

        // Distribute rewards
        stake.calculateTotalEligible();
        assertEq(stake.totalStaked(), stake.totalEligible());
        stake.distributeRewards(10);

        // Both stakers should have received rewards
        uint256 platformShare = (rewardAmount * friendKey.devPerformanceFeePercent()) / friendKey.BPS_SCALE();
        uint256 creatorShare = (rewardAmount * friendKey.creatorPerformanceFeePercent()) / friendKey.BPS_SCALE();
        rewardAmount -= platformShare + creatorShare;
        uint256 staker1Reward = (rewardAmount * 2) / expectedStaked;
        uint256 staker2Reward = (rewardAmount * 3) / expectedStaked;
        assertEq(mockUsdc.balanceOf(staker1), staker1InitialBalance + staker1Reward);
        assertEq(mockUsdc.balanceOf(staker2), staker2InitialBalance + staker2Reward);

        assertEq(stake.totalStaked(), expectedStaked);
        assertEq(stake.isOpenForStaking(), true); // Staking should be reopened after distribution
    }

    function testDistributeRewardsLimit() public {
        // find the gas usage for different batch sizes
        uint256 batchSize = 1000;
        for (uint256 i = 0; i < 5; i++) {
            console.log("Trying batch size:", batchSize);
            assertTrue(stake.isOpenForStaking(), "Staking should be open");

            vm.pauseGasMetering(); // this loop would exceed gas limit of tests
            for (uint256 j = 0; j < batchSize; j++) {
                // Mint tokens to stakers
                address staker = vm.addr(j + 10);
                vm.startPrank(staker);
                mockUsdc.mint(staker, 1_000_000 * (10 ** 6));
                uint256 price1 = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);
                mockUsdc.approve(address(friendKey), price1);
                friendKey.buyShares(CREATOR_TOKEN_ID, 1);
                // friendKey.safeTransferFrom(staker, address(stake), CREATOR_TOKEN_ID, 1, "");
                vm.stopPrank();
            }
            vm.resumeGasMetering();
            // Fund rewards
            uint256 rewardAmount = 1_000 * (10 ** 6);
            mockUsdc.mint(address(stake), rewardAmount);

            // Owner closes staking
            vm.prank(owner);
            stake.lockStaking();
            vm.startSnapshotGas("distribution");

            stake.distributeRewards(batchSize + 1);
            uint256 gasUsed = vm.stopSnapshotGas();
            console.log("Gas used for batch size", batchSize, ":", gasUsed);
            batchSize += 1000;
        }
    }

    function testCannotStakeWhenClosed() public {
        // Owner closes staking
        vm.prank(owner);
        stake.lockStaking();
        assertEq(stake.isOpenForStaking(), false);
        // Staker1 tries to stake
        vm.startPrank(staker1);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 1);
        vm.expectRevert("FriendStake: Staking is not open");
        friendKey.safeTransferFrom(staker1, address(stake), CREATOR_TOKEN_ID, 1, "");
        vm.stopPrank();
    }
}
