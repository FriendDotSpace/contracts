// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendPool} from "src/FriendPool.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {DlnOrderLib} from "src/libraries/DlnOrderLib.sol";
import {Errors} from "src/libraries/Errors.sol";

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

contract RevertingMock {
    function alwaysRevert() external pure {
        revert("Always reverts");
    }
}

// Minimal mock for dlnSource
contract DlnSourceMock {
    function createSaltedOrder(
        DlnOrderLib.OrderCreation calldata orderCreation,
        uint64, // salt
        bytes calldata,
        uint32,
        bytes calldata,
        bytes calldata
    ) external payable returns (bytes32) {
        require(orderCreation.giveTokenAddress == address(0), "Invalid give token address");
        return bytes32(uint256(0x1234));
    }
}

contract FriendPoolTest is Test {
    FriendKey public friendKey;
    FriendPool public friendPool;
    MockERC20 public mockUsdc;
    RevertingMock public revertingMock;
    DlnSourceMock public dlnSourceMock;

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
    uint256 public constant DEV_PERFORMANCE_FEE_PERCENT = 500;
    uint256 public constant CREATOR_PERFORMANCE_FEE_PERCENT = 1500;
    uint256 public CREATOR_TOKEN_ID = 1;

    uint256 private constant OWNER_PRIVATE_KEY = 1;
    bytes32 private constant REGISTER_CREATOR_TYPEHASH = keccak256(
        "RegisterCreator(address account,uint8 roomType,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)"
    );
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256(bytes("FriendKey"));
    bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(friendKey)));
    }

    function _getRegisterCreatorSignature(
        address account,
        FriendKey.RoomTier tier,
        uint256 additionalKeys,
        string memory metadata
    ) internal view returns (bytes memory) {
        return _getRegisterCreatorSignature(account, FriendKey.RoomType.Trading, tier, additionalKeys, metadata);
    }

    function _getRegisterCreatorSignature(
        address account,
        FriendKey.RoomType roomType,
        FriendKey.RoomTier tier,
        uint256 additionalKeys,
        string memory metadata
    ) internal view returns (bytes memory) {
        uint256 nonce = friendKey.registerCreatorNonces(account);
        bytes32 metadataHash = keccak256(bytes(metadata));
        bytes32 structHash = keccak256(
            abi.encode(
                REGISTER_CREATOR_TYPEHASH, account, uint8(roomType), uint8(tier), additionalKeys, nonce, metadataHash
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function setUp() public {
        owner = vm.addr(1);
        devFeeDestination = vm.addr(2);
        tradingPoolFeeDestination = vm.addr(4);
        creatorAccount = vm.addr(5);
        buyerAccount = vm.addr(6);
        anotherBuyerAccount = vm.addr(7);

        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
        revertingMock = new RevertingMock();
        dlnSourceMock = new DlnSourceMock();
        // Deploy FriendStake beacon
        address friendStakeBeacon = Upgrades.deployBeacon("FriendStake.sol", owner);

        vm.startPrank(owner);

        // Deploy FriendKey
        // Deploy and setup RoomManager for testing
        bytes memory roomManagerInitData = abi.encodeCall(FriendRoomManager.initialize, (owner));
        address roomManagerProxy = Upgrades.deployUUPSProxy("FriendRoomManager.sol", roomManagerInitData);
        FriendRoomManager roomManager = FriendRoomManager(roomManagerProxy);

        bytes memory friendKeyInitializeData =
            abi.encodeCall(FriendKey.initialize, (owner, address(mockUsdc), friendStakeBeacon, address(roomManager)));
        address friendKeyProxy = Upgrades.deployUUPSProxy("FriendKey.sol", friendKeyInitializeData);
        friendKey = FriendKey(friendKeyProxy);

        // Set FriendKey address in RoomManager
        roomManager.setFriendKey(address(friendKey));

        // Set fee destinations in RoomManager - CRITICAL for FriendPool tests
        // Note: friendPool is deployed after this, so we need to set it later

        // Deploy FriendPool
        bytes memory friendPoolInitializeData =
            abi.encodeCall(FriendPool.initialize, (owner, address(friendKey), address(dlnSourceMock)));
        address friendPoolProxy = Upgrades.deployUUPSProxy("FriendPool.sol", friendPoolInitializeData);
        friendPool = FriendPool(friendPoolProxy);

        // Now set the correct fee destinations
        roomManager.setFeeDestinations(owner, address(friendPool));

        // Set fees after initialization - CRITICAL: Without this, no fees are collected!
        // Fee setting moved to FriendRoomManager
        // friendKey.setTradingFees(uint16(DEV_FEE_PERCENT), uint16(CREATOR_FEE_PERCENT), uint16(TRADING_POOL_FEE_PERCENT));
        // Fee setting moved to FriendRoomManager
        // friendKey.setPerformanceFees(uint16(DEV_PERFORMANCE_FEE_PERCENT), uint16(CREATOR_PERFORMANCE_FEE_PERCENT));
        // friendKey.setSocialFees(uint16(DEV_FEE_PERCENT / 2), uint16(CREATOR_FEE_PERCENT));

        // Set FriendPool as trading pool fee destination in FriendKey
        // Fee setting moved to FriendRoomManager
        // Fee destination setting moved to FriendRoomManager
        // friendKey.setDevFeeDestination(owner);
        // friendKey.setTradingPoolFeeDestination(address(friendPool));

        // Verify fees are set correctly
        // Fee variables moved to FriendRoomManager
        // require(friendKey.tradingPoolFeePercent() == TRADING_POOL_FEE_PERCENT, "Trading pool fee not set");
        // Fee destination variables moved to FriendRoomManager
        // require(friendKey.tradingPoolFeeDestination() == address(friendPool), "Pool destination not set");

        vm.stopPrank();

        vm.startPrank(creatorAccount);
        // Register creator
        string memory metadata = "POOL_CREATOR";
        bytes memory signature = _getRegisterCreatorSignature(
            creatorAccount, FriendKey.RoomType.Trading, FriendKey.RoomTier.Club, 0, metadata
        );
        friendKey.registerCreator(metadata, signature);
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
        friendKey.buyShares(tokenId, amount, type(uint256).max);
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

        vm.expectRevert(Errors.NotFriendKey.selector);
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
        vm.expectRevert(Errors.ZeroAddress.selector);
        friendPool.setDispatcher(address(0));
        vm.stopPrank();
    }

    // Helper to create a dummy DlnOrderLib.OrderCreation struct
    function _dummyOrderCreation(uint256 amount) internal view returns (DlnOrderLib.OrderCreation memory) {
        return DlnOrderLib.OrderCreation({
            giveTokenAddress: address(0),
            giveAmount: amount,
            takeTokenAddress: "",
            takeAmount: 0,
            takeChainId: 0,
            receiverDst: "",
            givePatchAuthoritySrc: address(0),
            orderAuthorityAddressDst: "",
            allowedTakerDst: "",
            externalCall: "",
            allowedCancelBeneficiarySrc: ""
        });
    }

    function _ensureSufficientReserves(address buyer, uint256 tokenId)
        internal
        returns (uint256 poolBalance, uint256 netAmount, uint256 fee)
    {
        fee = friendPool.dispatchFee();
        poolBalance = friendPool.poolReserves(tokenId);
        // Keep buying until reserves exceed the dispatch fee.
        while (poolBalance <= fee) {
            _buyShares(buyer, tokenId, 10);
            poolBalance = friendPool.poolReserves(tokenId);
        }
        netAmount = poolBalance - fee;
    }

    function testDispatchByDispatcher() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 5);

        (uint256 poolBalance, uint256 netAmount,) = _ensureSufficientReserves(buyerAccount, CREATOR_TOKEN_ID);

        // Set dispatcher
        vm.startPrank(owner);
        friendPool.setDispatcher(creatorAccount);
        vm.stopPrank();

        // Prepare dummy order creation struct
        DlnOrderLib.OrderCreation memory orderCreation = _dummyOrderCreation(netAmount);

        // Dispatcher dispatches funds
        vm.startPrank(creatorAccount);
        vm.expectEmit(true, true, false, true);
        emit FriendPool.FundsDispatched(CREATOR_TOKEN_ID, netAmount, bytes32(uint256(0x1234)));

        uint256 dispatchedAmount = friendPool.dispatchAs(CREATOR_TOKEN_ID, orderCreation, 1);
        vm.stopPrank();

        // Verify dispatch results
        assertEq(dispatchedAmount, netAmount, "Dispatched amount should equal net pool balance");
        assertEq(friendPool.poolReserves(CREATOR_TOKEN_ID), 0, "Pool reserves should be zero after dispatch");
        assertEq(
            mockUsdc.allowance(address(friendPool), address(dlnSourceMock)),
            netAmount,
            "Target should have allowance for dispatched net amount"
        );
    }

    function testDispatchByOwner() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 3);

        (uint256 poolBalance, uint256 netAmount,) = _ensureSufficientReserves(buyerAccount, CREATOR_TOKEN_ID);

        // Prepare dummy order creation struct
        DlnOrderLib.OrderCreation memory orderCreation = _dummyOrderCreation(netAmount);

        // Owner dispatches funds
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit FriendPool.FundsDispatched(CREATOR_TOKEN_ID, netAmount, bytes32(uint256(0x1234)));

        uint256 dispatchedAmount = friendPool.dispatchAs(CREATOR_TOKEN_ID, orderCreation, 1);
        vm.stopPrank();

        // Verify dispatch results
        assertEq(dispatchedAmount, netAmount, "Dispatched amount should equal net pool balance");
        assertEq(friendPool.poolReserves(CREATOR_TOKEN_ID), 0, "Pool reserves should be zero after dispatch");
        assertEq(
            mockUsdc.allowance(address(friendPool), address(dlnSourceMock)),
            netAmount,
            "Target should have allowance for dispatched net amount"
        );
    }

    function testDispatchFailsForNonDispatcherNonOwner() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);

        DlnOrderLib.OrderCreation memory orderCreation = _dummyOrderCreation(friendPool.poolReserves(CREATOR_TOKEN_ID));

        // Non-dispatcher/non-owner tries to dispatch (should fail)
        vm.startPrank(buyerAccount);
        vm.expectRevert(Errors.NotDispatcher.selector);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, orderCreation, 1);
        vm.stopPrank();
    }

    function testDispatchFailsForNonOwner() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);

        DlnOrderLib.OrderCreation memory orderCreation = _dummyOrderCreation(friendPool.poolReserves(CREATOR_TOKEN_ID));

        // Non-owner tries to dispatch as owner (should fail)
        vm.startPrank(buyerAccount);
        vm.expectRevert(Errors.NotDispatcher.selector);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, orderCreation, 1);
        vm.stopPrank();
    }

    function testDispatchFailsWithZeroBalance() public {
        // Try to dispatch when pool has no balance
        DlnOrderLib.OrderCreation memory orderCreation = _dummyOrderCreation(0);

        vm.startPrank(owner);
        vm.expectRevert(Errors.NoFundsAvailable.selector);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, orderCreation, 1);
        vm.stopPrank();
    }

    function testDispatchCreatesCorrectApproval() public {
        // Setup: Generate some fees in the pool
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 4);

        (uint256 poolBalance, uint256 netAmount,) = _ensureSufficientReserves(buyerAccount, CREATOR_TOKEN_ID);

        DlnOrderLib.OrderCreation memory orderCreation = _dummyOrderCreation(netAmount);

        // Check initial allowance
        assertEq(mockUsdc.allowance(address(friendPool), address(dlnSourceMock)), 0, "Initial allowance should be zero");

        // Owner dispatches funds
        vm.startPrank(owner);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, orderCreation, 1);
        vm.stopPrank();

        // Check final allowance
        assertEq(
            mockUsdc.allowance(address(friendPool), address(dlnSourceMock)),
            netAmount,
            "Final allowance should equal dispatched net amount"
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
        (uint256 totalReserves, uint256 netAmount,) = _ensureSufficientReserves(anotherBuyerAccount, CREATOR_TOKEN_ID);
        assertGt(totalReserves, firstReserves, "Total reserves should be greater than first trade");

        // Partial dispatch (dispatch all available)
        DlnOrderLib.OrderCreation memory orderCreation = _dummyOrderCreation(netAmount);

        vm.startPrank(owner);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, orderCreation, 1);
        vm.stopPrank();

        assertEq(friendPool.poolReserves(CREATOR_TOKEN_ID), 0, "Reserves should be zero after dispatch");
    }

    function testMultipleTokenIdReserves() public {
        // Register another creator
        vm.startPrank(anotherBuyerAccount);
        string memory metadata = "SECOND_CREATOR";
        bytes memory signature = _getRegisterCreatorSignature(
            anotherBuyerAccount, FriendKey.RoomType.Trading, FriendKey.RoomTier.Club, 0, metadata
        );
        uint256 secondTokenId = friendKey.registerCreator(metadata, signature);
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
        (, uint256 netAmount,) = _ensureSufficientReserves(buyerAccount, CREATOR_TOKEN_ID);
        DlnOrderLib.OrderCreation memory orderCreation = _dummyOrderCreation(netAmount);

        vm.startPrank(owner);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, orderCreation, 1);
        vm.stopPrank();

        assertEq(friendPool.poolReserves(CREATOR_TOKEN_ID), 0, "First token reserves should be zero after dispatch");
        assertEq(
            friendPool.poolReserves(secondTokenId), secondTokenReserves, "Second token reserves should be unchanged"
        );
    }

    // Pause tests
    function testPause_PullRevertsWhenPaused() public {
        // First generate some fees
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);

        address roomManagerAddr = friendKey.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        // Pause the contract
        vm.prank(owner);
        roomManager.pause();

        // Try to pull - should revert (this is called by FriendKey during buy/sell)
        // We can't directly call pull since it's onlyFriendKey, but we can test that buy/sell reverts
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(friendKey), type(uint256).max);
        vm.expectRevert(Errors.ContractPaused.selector);
        friendKey.buyShares(CREATOR_TOKEN_ID, 1, type(uint256).max);
        vm.stopPrank();
    }

    function testPause_DispatchRevertsWhenPaused() public {
        // First generate some fees
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);

        address roomManagerAddr = friendKey.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        // Pause the contract
        vm.prank(owner);
        roomManager.pause();

        // Try to dispatch - should revert
        DlnOrderLib.OrderCreation memory orderCreation = _dummyOrderCreation(friendPool.poolReserves(CREATOR_TOKEN_ID));
        vm.startPrank(owner);
        vm.expectRevert(Errors.ContractPaused.selector);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, orderCreation, 1);
        vm.stopPrank();
    }

    function testPause_OperationsWorkAfterUnpause() public {
        address roomManagerAddr = friendKey.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        // Pause the contract
        vm.prank(owner);
        roomManager.pause();

        // Unpause the contract
        vm.prank(owner);
        roomManager.unpause();

        // Operations should work again
        _buyShares(buyerAccount, CREATOR_TOKEN_ID, 2);

        (, uint256 netAmount,) = _ensureSufficientReserves(buyerAccount, CREATOR_TOKEN_ID);
        DlnOrderLib.OrderCreation memory orderCreation = _dummyOrderCreation(netAmount);
        vm.startPrank(owner);
        friendPool.dispatchAs(CREATOR_TOKEN_ID, orderCreation, 1);
        vm.stopPrank();
    }
}
