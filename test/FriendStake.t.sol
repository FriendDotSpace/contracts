// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendStake} from "src/FriendStake.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {Errors} from "src/libraries/Errors.sol";

// Use the same MockERC20 from FriendKey.t.sol
import {MockERC20, MockPool} from "./FriendKey.t.sol";

contract FriendStakeTest is Test {
    FriendKey public friendKey;
    FriendStake public stake;
    FriendRoomManager public roomManager;
    MockERC20 public mockUsdc;

    address public owner;
    address public devFeeDestination;
    address public tradingPoolFeeDestination;
    address public creatorAccount;
    address public staker1;
    address public staker2;

    uint256 public CREATOR_TOKEN_ID = 1;
    uint256 private constant OWNER_PRIVATE_KEY = 1;
    bytes32 private constant REGISTER_CREATOR_TYPEHASH =
        keccak256("RegisterCreator(address account,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256(bytes("FriendKey"));
    bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

    function setUp() public {
        owner = vm.addr(1);
        devFeeDestination = vm.addr(2);
        creatorAccount = vm.addr(5);
        staker1 = vm.addr(6);
        staker2 = vm.addr(7);

        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);

        MockPool pool = new MockPool(address(mockUsdc));
        tradingPoolFeeDestination = address(pool);
        // Deploy FriendStake beacon
        address friendStakeBeacon = Upgrades.deployBeacon("FriendStake.sol", owner);

        vm.startPrank(owner);
        bytes memory roomManagerInitData = abi.encodeCall(FriendRoomManager.initialize, (owner));
        address roomManagerProxy = Upgrades.deployUUPSProxy("FriendRoomManager.sol", roomManagerInitData);
        roomManager = FriendRoomManager(roomManagerProxy);

        bytes memory initializeData =
            abi.encodeCall(FriendKey.initialize, (owner, address(mockUsdc), friendStakeBeacon, address(roomManager)));
        address proxy = Upgrades.deployUUPSProxy("FriendKey.sol", initializeData);
        friendKey = FriendKey(proxy);

        roomManager.setFriendKey(address(friendKey));

        roomManager.setFeeDestinations(devFeeDestination, tradingPoolFeeDestination);
        vm.stopPrank();

        // Register creator and mint initial share
        vm.startPrank(creatorAccount);
        string memory metadata = "";
        bytes memory signature = _getRegisterCreatorSignature(creatorAccount, FriendKey.RoomTier.Club, 0, metadata);
        friendKey.registerCreator(metadata, signature);
        stake = FriendStake(friendKey.stakingPoolByTokenId(CREATOR_TOKEN_ID));
        vm.stopPrank();

        // Mint tokens to stakers
        mockUsdc.mint(creatorAccount, 1_000_000 * (10 ** 6));
        mockUsdc.mint(staker1, 1_000_000 * (10 ** 6));
        mockUsdc.mint(staker2, 1_000_000 * (10 ** 6));
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(friendKey)));
    }

    function _getRegisterCreatorSignature(
        address account,
        FriendKey.RoomTier tier,
        uint256 additionalKeys,
        string memory metadata
    ) internal view returns (bytes memory) {
        uint256 nonce = friendKey.registerCreatorNonces(account);
        bytes32 metadataHash = keccak256(bytes(metadata));
        bytes32 structHash =
            keccak256(abi.encode(REGISTER_CREATOR_TYPEHASH, account, uint8(tier), additionalKeys, nonce, metadataHash));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function testStakeSingleShare() public {
        // Creator buys another share to stake
        vm.startPrank(creatorAccount);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 1, 0);

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
        friendKey.buyShares(CREATOR_TOKEN_ID, 3, 0);

        // First stake the shares
        friendKey.stake(CREATOR_TOKEN_ID, 3);
        assertEq(stake.totalStaked(), 3); // 3 shares staked

        // Now unstake 2 shares to test batch staking
        friendKey.unstake(CREATOR_TOKEN_ID, 2);
        assertEq(stake.totalStaked(), 1);

        // Approve and stake 2 shares in batch
        friendKey.setApprovalForAll(address(stake), true);
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = CREATOR_TOKEN_ID;
        amounts[0] = 1;
        ids[1] = CREATOR_TOKEN_ID;
        amounts[1] = 1;
        friendKey.safeBatchTransferFrom(staker1, address(stake), ids, amounts, "");

        assertEq(stake.totalStaked(), 3); // 1 remaining from previous stake + 2 new batch stake
        vm.stopPrank();
    }

    function testUnstake() public {
        // Staker1 buys and stakes
        vm.startPrank(staker1);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 2);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 2, 0);
        friendKey.stake(CREATOR_TOKEN_ID, 2);
        assertEq(stake.totalStaked(), 2);

        // Unstake 1
        stake.unstake(1);
        assertEq(stake.totalStaked(), 1);
        // Unstake remaining
        stake.unstakeAll();
        assertEq(stake.totalStaked(), 0); // 1 initial share by owner remains staked
        vm.stopPrank();
    }

    function testClaimRewards() public {
        // Staker1 buys and stakes
        vm.startPrank(staker1);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 2);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 2, 0);
        friendKey.stake(CREATOR_TOKEN_ID, 2);
        vm.stopPrank();
        assertEq(stake.totalStaked(), 2); // 2 shares staked

        // Simulate rewards by minting USDC to the stake contract
        uint256 rewardAmount = 1_000 * (10 ** 6);
        mockUsdc.mint(address(stake), rewardAmount);

        // Owner closes staking
        vm.warp(block.timestamp + 1 days); // Ensure enough time has passed for rewards to be eligible
        vm.prank(owner);
        stake.lockStaking();
        stake.calculateTotalEligible(10);
        assertEq(stake.isOpenForStaking(), false);

        // Claim rewards
        uint256 initialBalance = mockUsdc.balanceOf(staker1);
        vm.prank(staker1);
        stake.claim();
        uint256 finalBalance = mockUsdc.balanceOf(staker1);

        // Check if rewards were claimed correctly
        assertTrue(finalBalance > initialBalance, "Staker should have received rewards");
    }

    function testDistributeRewards() public {
        // Staker1 and Staker2 buy and stake
        vm.startPrank(staker1);
        uint256 price1 = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 2);
        mockUsdc.approve(address(friendKey), price1);
        friendKey.buyShares(CREATOR_TOKEN_ID, 2, 0);
        friendKey.stake(CREATOR_TOKEN_ID, 2);
        vm.stopPrank();

        vm.startPrank(staker2);
        uint256 price2 = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 3);
        mockUsdc.approve(address(friendKey), price2);
        friendKey.buyShares(CREATOR_TOKEN_ID, 3, 0);
        friendKey.stake(CREATOR_TOKEN_ID, 3);
        vm.stopPrank();

        // Fund rewards
        uint256 rewardAmount = 1_000 * (10 ** 6);
        mockUsdc.mint(address(stake), rewardAmount);

        // Owner closes staking
        vm.warp(block.timestamp + 1 days); // Ensure enough time has passed for rewards to be eligible
        vm.prank(owner);
        stake.lockStaking();
        assertEq(stake.isOpenForStaking(), false);
        uint256 expectedStaked = 5;
        assertEq(stake.totalStaked(), expectedStaked); // 2 from staker1 + 3 from staker2

        // Check initial balances
        uint256 staker1InitialBalance = mockUsdc.balanceOf(staker1);
        uint256 staker2InitialBalance = mockUsdc.balanceOf(staker2);

        // Distribute rewards
        vm.prank(owner);
        stake.calculateTotalEligible(10);
        assertEq(stake.totalStaked(), stake.totalEligible());
        vm.prank(owner);
        stake.distributeRewards(10);

        (uint16 devPerformanceFee, uint16 creatorPerformanceFee) = friendKey.getPerformanceFees();
        // Both stakers should have received rewards
        uint256 platformShare = (rewardAmount * devPerformanceFee) / friendKey.BPS_SCALE();
        uint256 creatorShare = (rewardAmount * creatorPerformanceFee) / friendKey.BPS_SCALE();
        rewardAmount -= platformShare + creatorShare;
        uint256 staker1Reward = (rewardAmount * 2) / expectedStaked;
        uint256 staker2Reward = (rewardAmount * 3) / expectedStaked;
        assertEq(mockUsdc.balanceOf(staker1), staker1InitialBalance + staker1Reward);
        assertEq(mockUsdc.balanceOf(staker2), staker2InitialBalance + staker2Reward);

        assertEq(stake.totalStaked(), expectedStaked);
        assertEq(stake.isOpenForStaking(), true); // Staking should be reopened after distribution
    }

    function skip_testDistributeRewardsLimit() public {
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
                friendKey.buyShares(CREATOR_TOKEN_ID, 1, 0);
                friendKey.stake(CREATOR_TOKEN_ID, 1);
                vm.stopPrank();
            }
            vm.resumeGasMetering();
            // Fund rewards
            uint256 rewardAmount = 1_000 * (10 ** 6);
            mockUsdc.mint(address(stake), rewardAmount);

            // Owner closes staking
            vm.warp(block.timestamp + 1 days);
            vm.prank(owner);
            stake.lockStaking();
            vm.prank(owner);
            stake.calculateTotalEligible(batchSize + 1);
            vm.startSnapshotGas("distribution");
            vm.prank(owner);
            stake.distributeRewards(batchSize + 1);
            uint256 gasUsed = vm.stopSnapshotGas();
            console.log("Gas used for batch size", batchSize, ":", gasUsed);
            batchSize += 1000;
        }
    }

    function testCannotStakeWhenClosed() public {
        // Owner closes staking
        vm.expectRevert("FriendStake: No rewards to distribute");
        vm.prank(owner);
        stake.lockStaking();
        mockUsdc.mint(address(stake), 10 * (10 ** 6));
        vm.prank(owner);
        stake.lockStaking();
        assertEq(stake.isOpenForStaking(), false);
        // Staker1 tries to stake
        vm.startPrank(staker1);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 1, 0);
        vm.expectRevert("FriendStake: Staking is not open");
        friendKey.safeTransferFrom(staker1, address(stake), CREATOR_TOKEN_ID, 1, "");
        vm.stopPrank();
    }

    // Pause tests
    function testPause_StakeRevertsWhenPaused() public {
        vm.startPrank(staker1);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 1, 0);
        friendKey.setApprovalForAll(address(stake), true);
        vm.stopPrank();

        // Now pause the contract
        vm.prank(owner);
        roomManager.pause();

        // Try to stake - should revert
        vm.startPrank(staker1);
        vm.expectRevert(Errors.ContractPaused.selector);
        friendKey.stake(CREATOR_TOKEN_ID, 1);
        vm.stopPrank();
    }

    function testPause_UnstakeRevertsWhenPaused() public {
        // First stake some tokens
        vm.startPrank(staker1);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 1, 0);
        friendKey.setApprovalForAll(address(stake), true);
        friendKey.stake(CREATOR_TOKEN_ID, 1);
        vm.stopPrank();

        // Pause the contract
        vm.prank(owner);
        roomManager.pause();

        // Try to unstake - should revert
        vm.startPrank(staker1);
        vm.expectRevert(Errors.ContractPaused.selector);
        friendKey.unstake(CREATOR_TOKEN_ID, 1);
        vm.stopPrank();
    }

    function testPause_ClaimRevertsWhenPaused() public {
        // Setup: stake, lock, and fund rewards
        vm.startPrank(staker1);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 1, 0);
        friendKey.setApprovalForAll(address(stake), true);
        friendKey.stake(CREATOR_TOKEN_ID, 1);
        vm.stopPrank();

        // Fund rewards and lock staking
        mockUsdc.mint(address(stake), 10 * (10 ** 6));
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        stake.lockStaking();
        vm.prank(owner);
        stake.calculateTotalEligible(10);

        // Pause the contract
        vm.prank(owner);
        roomManager.pause();

        // Try to claim - should revert
        vm.startPrank(staker1);
        vm.expectRevert(Errors.ContractPaused.selector);
        stake.claim();
        vm.stopPrank();
    }

    function testPause_OperationsWorkAfterUnpause() public {
        // Pause the contract
        vm.prank(owner);
        roomManager.pause();

        // Unpause the contract
        vm.prank(owner);
        roomManager.unpause();

        // Operations should work again
        vm.startPrank(staker1);
        uint256 price = friendKey.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);
        mockUsdc.approve(address(friendKey), price);
        friendKey.buyShares(CREATOR_TOKEN_ID, 1, 0);
        friendKey.setApprovalForAll(address(stake), true);
        friendKey.stake(CREATOR_TOKEN_ID, 1);
        vm.stopPrank();
    }
}
