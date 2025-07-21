// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendPool} from "src/FriendPool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// Simple Mock ERC20 for testing purposes
contract MockERC20 is IERC20Metadata {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;
    uint256 public totalSupply;
    string public name;
    string public symbol;
    uint8 public _decimals;

    constructor(string memory _name, string memory _symbol, uint8 __decimals) {
        name = _name;
        symbol = _symbol;
        _decimals = __decimals;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        balances[msg.sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        allowances[sender][msg.sender] -= amount;
        balances[sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function mint(address account, uint256 amount) external {
        balances[account] += amount;
        totalSupply += amount;
        emit Transfer(address(0), account, amount);
    }
}

contract DispatchTargetMock {
    uint256 public receivedAmount;
    address public receivedFrom;
    bytes public receivedData;

    receive() external payable {
        receivedAmount = msg.value;
        receivedFrom = msg.sender;
    }

    function handleDispatch(bytes calldata data) external {
        receivedData = data;
        receivedFrom = msg.sender;
        console2.log("Dispatch handled with data:", string(data));
    }
}

contract RevertingMock {
    function alwaysRevert() external pure {
        revert("Always reverts");
    }
}

contract FriendPoolTest is Test {
    FriendKey public friendKey;
    FriendPool public friendPool;
    MockERC20 public mockUsdc;
    DispatchTargetMock public dispatchTarget;
    RevertingMock public revertingMock;

    using Strings for uint256;

    address public owner;
    address public devFeeDestination;
    address public creatorFeePercentDestination;
    address public tradingPoolFeeDestination;
    address public creatorAccount;
    address public buyerAccount;
    address public anotherBuyerAccount;

    uint256 public constant DEV_FEE_PERCENT = 100;
    uint256 public constant CREATOR_FEE_PERCENT = 100;
    uint256 public constant TRADING_POOL_FEE_PERCENT = 100;
    uint256 public CREATOR_TOKEN_ID = 1;

    function setUp() public {
        owner = vm.addr(1);
        devFeeDestination = vm.addr(2);
        tradingPoolFeeDestination = vm.addr(4);
        creatorAccount = vm.addr(5);
        buyerAccount = vm.addr(6);
        anotherBuyerAccount = vm.addr(7);

        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
        dispatchTarget = new DispatchTargetMock();
        revertingMock = new RevertingMock();

        vm.startPrank(owner);

        // Deploy FriendKey
        bytes memory friendKeyInitializeData = abi.encodeCall(
            FriendKey.initialize,
            (
                owner,
                devFeeDestination,
                DEV_FEE_PERCENT,
                CREATOR_FEE_PERCENT,
                address(0), // We'll set this after FriendPool is deployed
                TRADING_POOL_FEE_PERCENT,
                address(mockUsdc)
            )
        );
        address friendKeyProxy = Upgrades.deployUUPSProxy("FriendKey.sol", friendKeyInitializeData);
        friendKey = FriendKey(friendKeyProxy);

        // Deploy FriendPool
        bytes memory friendPoolInitializeData = abi.encodeCall(FriendPool.initialize, (owner, address(friendKey)));
        address friendPoolProxy = Upgrades.deployUUPSProxy("FriendPool.sol", friendPoolInitializeData);
        friendPool = FriendPool(friendPoolProxy);

        // Set FriendPool as trading pool fee destination in FriendKey
        friendKey.setTradingPoolFeeDestination(address(friendPool));

        vm.stopPrank();

        vm.startPrank(creatorAccount);
        // Register creator
        friendKey.registerCreator();
        assertEq(friendKey.creatorByTokenId(CREATOR_TOKEN_ID), creatorAccount, "TOKEN_ID mismatch");
        vm.stopPrank();

        mockUsdc.mint(creatorAccount, 1_000_000 * (10 ** 6));
        mockUsdc.mint(buyerAccount, 1_000_000 * (10 ** 6));
        mockUsdc.mint(anotherBuyerAccount, 1_000_000 * (10 ** 6));
    }

    // Test helper function to simulate buy shares transaction
    function _buyShares(address buyer, uint256 tokenId, uint256 amount) internal {
        vm.startPrank(buyer);
        uint256 cost = friendKey.getBuyPriceAfterFee(tokenId, amount);
        mockUsdc.approve(address(friendKey), cost);
        friendKey.buyShares(tokenId, amount);
        vm.stopPrank();
    }

    // Helper function to calculate expected trading pool fee
    function _calculateExpectedTradingPoolFee(uint256 tokenId, uint256 amount) internal view returns (uint256) {
        uint256 price = friendKey.getBuyPrice(tokenId, amount);
        return (price * TRADING_POOL_FEE_PERCENT) / 10000;
    }

    // Test pulling funds from FriendKey to FriendPool
    function testPullFunds() public {
        // Buy shares to generate trading pool fees
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 5);

        // The pool reserves should be non-zero after the trade
        uint256 actualReserves = friendPool.poolReserves(CREATOR_TOKEN_ID);
        assertGt(actualReserves, 0, "Pool should have some reserves after trade");

        // Check that FriendPool received the fees
        assertEq(
            mockUsdc.balanceOf(address(friendPool)),
            actualReserves,
            "FriendPool USDC balance should match pool reserves"
        );
    }

    function testPullFundsMultipleTrades() public {
        // First trade
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 3);
        uint256 firstReserves = friendPool.poolReserves(CREATOR_TOKEN_ID);

        // Second trade
        _buyShares(anotherBuyerAccount, CREATOR_TOKEN_ID, 2);
        uint256 totalReserves = friendPool.poolReserves(CREATOR_TOKEN_ID);

        // Check that reserves accumulate
        assertGt(firstReserves, 0, "First trade should generate some reserves");
        assertGt(totalReserves, firstReserves, "Total reserves should be greater than first trade reserves");
        assertEq(
            mockUsdc.balanceOf(address(friendPool)),
            totalReserves,
            "FriendPool USDC balance should match total reserves"
        );
    }

    function testPullFundsOnlyFromFriendKey() public {
        // Try to call pull directly (should fail)
        vm.startPrank(creatorAccount);
        mockUsdc.approve(address(friendPool), 1000);

        vm.expectRevert("FriendPool: Caller is not the FriendKey contract");
        friendPool.pull(CREATOR_TOKEN_ID, 1000);
        vm.stopPrank();
    }

    function testSetDispatcher() public {
        // Only owner can set dispatcher
        vm.startPrank(owner);
        friendPool.setDispatcher(creatorAccount);
        vm.stopPrank();

        // Non-owner cannot set dispatcher
        vm.startPrank(buyerAccount);
        vm.expectRevert();
        friendPool.setDispatcher(anotherBuyerAccount);
        vm.stopPrank();

        // Cannot set zero address as dispatcher
        vm.startPrank(owner);
        vm.expectRevert("FriendPool: Dispatcher address cannot be zero");
        friendPool.setDispatcher(address(0));
        vm.stopPrank();
    }

    function testDispatchByDispatcher() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 5);

        uint256 poolBalance = friendPool.poolReserves(CREATOR_TOKEN_ID);
        assertGt(poolBalance, 0, "Pool should have some balance before dispatch");

        // Set dispatcher
        vm.startPrank(owner);
        friendPool.setDispatcher(creatorAccount);
        vm.stopPrank();

        // Prepare dispatch data
        bytes memory dispatchData =
            abi.encodeWithSelector(DispatchTargetMock.handleDispatch.selector, bytes("test dispatch data"));

        // Dispatcher dispatches funds
        vm.startPrank(creatorAccount);
        vm.expectEmit(true, true, false, true);
        emit FriendPool.FundsDispatched(CREATOR_TOKEN_ID, address(dispatchTarget), poolBalance);

        uint256 dispatchedAmount = friendPool.dispatchAs(CREATOR_TOKEN_ID, address(dispatchTarget), dispatchData);
        vm.stopPrank();

        // Verify dispatch results
        assertEq(dispatchedAmount, poolBalance, "Dispatched amount should equal pool balance");
        assertEq(friendPool.poolReserves(CREATOR_TOKEN_ID), 0, "Pool reserves should be zero after dispatch");
        assertEq(
            mockUsdc.allowance(address(friendPool), address(dispatchTarget)),
            poolBalance,
            "Target should have allowance for dispatched amount"
        );
    }

    function testDispatchByOwner() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 3);

        uint256 poolBalance = friendPool.poolReserves(CREATOR_TOKEN_ID);
        assertGt(poolBalance, 0, "Pool should have some balance before dispatch");

        // Prepare dispatch data
        bytes memory dispatchData =
            abi.encodeWithSelector(DispatchTargetMock.handleDispatch.selector, bytes("owner dispatch data"));

        // Owner dispatches funds
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit FriendPool.FundsDispatched(CREATOR_TOKEN_ID, address(dispatchTarget), poolBalance);

        uint256 dispatchedAmount = friendPool.dispatchAs(CREATOR_TOKEN_ID, address(dispatchTarget), dispatchData);
        vm.stopPrank();

        // Verify dispatch results
        assertEq(dispatchedAmount, poolBalance, "Dispatched amount should equal pool balance");
        assertEq(friendPool.poolReserves(CREATOR_TOKEN_ID), 0, "Pool reserves should be zero after dispatch");
        assertEq(
            mockUsdc.allowance(address(friendPool), address(dispatchTarget)),
            poolBalance,
            "Target should have allowance for dispatched amount"
        );
    }

    function testDispatchFailsForNonDispatcherNonOwner() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);

        bytes memory dispatchData =
            abi.encodeWithSelector(DispatchTargetMock.handleDispatch.selector, bytes("unauthorized dispatch"));

        // Non-dispatcher/non-owner tries to dispatch (should fail)
        vm.startPrank(buyerAccount);
        vm.expectRevert("FriendPool: Caller is not the dispatcher");
        friendPool.dispatchAs(CREATOR_TOKEN_ID, address(dispatchTarget), dispatchData);
        vm.stopPrank();
    }

    function testDispatchFailsForNonOwner() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);

        bytes memory dispatchData =
            abi.encodeWithSelector(DispatchTargetMock.handleDispatch.selector, bytes("unauthorized dispatch"));

        // Non-owner tries to dispatch as owner (should fail)
        vm.startPrank(buyerAccount);
        vm.expectRevert("FriendPool: Caller is not the dispatcher");
        friendPool.dispatchAs(CREATOR_TOKEN_ID, address(dispatchTarget), dispatchData);
        vm.stopPrank();
    }

    function testDispatchFailsWithZeroBalance() public {
        // Try to dispatch when pool has no balance
        bytes memory dispatchData =
            abi.encodeWithSelector(DispatchTargetMock.handleDispatch.selector, bytes("empty pool dispatch"));

        vm.startPrank(owner);
        vm.expectRevert("FriendPool: No funds available for dispatch");
        friendPool.dispatchAs(CREATOR_TOKEN_ID, address(dispatchTarget), dispatchData);
        vm.stopPrank();
    }

    function testDispatchFailsWithZeroAddress() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);

        bytes memory dispatchData =
            abi.encodeWithSelector(DispatchTargetMock.handleDispatch.selector, bytes("zero address dispatch"));

        vm.startPrank(owner);
        vm.expectRevert("FriendPool: Recipient address cannot be zero");
        friendPool.dispatchAs(CREATOR_TOKEN_ID, address(0), dispatchData);
        vm.stopPrank();
    }

    function testDispatchFailsWithBadCalldata() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);

        // Create calldata that will cause the call to revert
        bytes memory badCalldata = abi.encodeWithSelector(RevertingMock.alwaysRevert.selector);

        vm.startPrank(owner);
        vm.expectRevert("FriendPool: Dispatch failed");
        friendPool.dispatchAs(CREATOR_TOKEN_ID, address(revertingMock), badCalldata);
        vm.stopPrank();
    }

    function testDispatchCreatesCorrectApproval() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 4);

        uint256 poolBalance = friendPool.poolReserves(CREATOR_TOKEN_ID);

        // Prepare dispatch data
        bytes memory dispatchData =
            abi.encodeWithSelector(DispatchTargetMock.handleDispatch.selector, bytes("approval test"));

        // Check initial allowance
        assertEq(
            mockUsdc.allowance(address(friendPool), address(dispatchTarget)), 0, "Initial allowance should be zero"
        );

        // Owner dispatches funds
        vm.startPrank(owner);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, address(dispatchTarget), dispatchData);
        vm.stopPrank();

        // Check final allowance
        assertEq(
            mockUsdc.allowance(address(friendPool), address(dispatchTarget)),
            poolBalance,
            "Final allowance should equal dispatched amount"
        );
    }

    function testPoolReservesTrackingAccuracy() public {
        // Test that pool reserves are accurately tracked across multiple operations
        uint256 initialReserves = friendPool.poolReserves(CREATOR_TOKEN_ID);
        assertEq(initialReserves, 0, "Initial reserves should be zero");

        // First trade
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);
        uint256 firstReserves = friendPool.poolReserves(CREATOR_TOKEN_ID);
        assertGt(firstReserves, 0, "First trade should generate reserves");

        // Second trade
        _buyShares(anotherBuyerAccount, CREATOR_TOKEN_ID, 3);
        uint256 totalReserves = friendPool.poolReserves(CREATOR_TOKEN_ID);
        assertGt(totalReserves, firstReserves, "Total reserves should be greater than first trade");

        // Partial dispatch (dispatch all available)
        bytes memory dispatchData =
            abi.encodeWithSelector(DispatchTargetMock.handleDispatch.selector, bytes("partial dispatch"));

        vm.startPrank(owner);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, address(dispatchTarget), dispatchData);
        vm.stopPrank();

        assertEq(friendPool.poolReserves(CREATOR_TOKEN_ID), 0, "Reserves should be zero after dispatch");
    }

    function testMultipleTokenIdReserves() public {
        // Register another creator
        vm.startPrank(anotherBuyerAccount);
        uint256 secondTokenId = friendKey.registerCreator();
        vm.stopPrank();

        // Generate fees for both tokens
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);
        _buyShares(creatorAccount, secondTokenId, 3);

        uint256 firstTokenReserves = friendPool.poolReserves(CREATOR_TOKEN_ID);
        uint256 secondTokenReserves = friendPool.poolReserves(secondTokenId);

        // Check that reserves are tracked separately
        assertGt(firstTokenReserves, 0, "First token should have some reserves");
        assertGt(secondTokenReserves, 0, "Second token should have some reserves");

        // Dispatch from first token should not affect second
        bytes memory dispatchData =
            abi.encodeWithSelector(DispatchTargetMock.handleDispatch.selector, bytes("multi-token dispatch"));

        vm.startPrank(owner);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, address(dispatchTarget), dispatchData);
        vm.stopPrank();

        assertEq(friendPool.poolReserves(CREATOR_TOKEN_ID), 0, "First token reserves should be zero after dispatch");
        assertEq(
            friendPool.poolReserves(secondTokenId), secondTokenReserves, "Second token reserves should be unchanged"
        );
    }
}
