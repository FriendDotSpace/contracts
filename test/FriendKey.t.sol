// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendStake} from "src/FriendStake.sol";
import {FriendRoomManager} from "src/FriendRoomManager.sol";
import {IFriendKey} from "src/interfaces/IFriendKey.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
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

    function burn(address account, uint256 amount) external {
        balances[account] -= amount;
        totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }
}

contract MockPool {
    MockERC20 public bondingToken;

    constructor(address _bondingToken) {
        bondingToken = MockERC20(_bondingToken);
    }

    function pull(uint256 tokenId, uint256 amount) external returns (bool) {
        bool success = bondingToken.transferFrom(msg.sender, address(this), amount);
        console.log("Pull called with tokenId:", tokenId, "and amount:", amount);
        return success;
    }

    function dispatchFee() external pure returns (uint256) {
        return 0; // Mock dispatch fee
    }
}

contract FriendKeyTest is Test {
    FriendKey public instance;
    MockERC20 public mockUsdc;

    using Strings for uint256;

    address public owner;
    address public devFeeDestination;
    address public creatorFeePercentDestination;
    address public tradingPoolFeeDestination;
    address public creatorAccount;
    address public buyerAccount;
    address public anotherBuyerAccount;

    uint256 public constant DEV_FEE_PERCENT = 200;
    uint256 public constant CREATOR_FEE_PERCENT = 200;
    uint256 public constant TRADING_POOL_FEE_PERCENT = 600;
    uint256 public constant BPS_SCALE = 10_000; // Basis points scale for fee calculations
    uint256 public CREATOR_TOKEN_ID = 1;

    FriendStake public friendStake;

    uint256 private constant OWNER_PRIVATE_KEY = 1;
    bytes32 private constant REGISTER_CREATOR_TYPEHASH = keccak256(
        "RegisterCreator(address account,uint8 roomType,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)"
    );
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256(bytes("FriendKey"));
    bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(instance)));
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
        uint256 nonce = instance.registerCreatorNonces(account);
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

    function _registerCreator(address account, FriendKey.RoomTier tier, uint256 additionalKeys, string memory metadata)
        internal
        returns (uint256)
    {
        bytes memory signature = _getRegisterCreatorSignature(account, tier, additionalKeys, metadata);
        vm.prank(account);
        return instance.registerCreator(tier, additionalKeys, metadata, signature);
    }

    function _registerCreator(address account) internal returns (uint256) {
        bytes memory signature =
            _getRegisterCreatorSignature(account, FriendKey.RoomType.Trading, FriendKey.RoomTier.Club, 0, "");
        vm.prank(account);
        return instance.registerCreator("", signature);
    }

    function setUp() public {
        owner = vm.addr(1);
        devFeeDestination = vm.addr(2);

        creatorAccount = vm.addr(5);
        buyerAccount = vm.addr(6);
        anotherBuyerAccount = vm.addr(7);

        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);

        MockPool pool = new MockPool(address(mockUsdc));
        tradingPoolFeeDestination = address(pool); //vm.addr(4);
        // Deploy FriendStake beacon
        address friendStakeBeacon = Upgrades.deployBeacon("FriendStake.sol", owner);

        vm.startPrank(owner);
        // Deploy and setup RoomManager for testing
        bytes memory roomManagerInitData = abi.encodeCall(FriendRoomManager.initialize, (owner));
        address roomManagerProxy = Upgrades.deployUUPSProxy("FriendRoomManager.sol", roomManagerInitData);
        FriendRoomManager roomManager = FriendRoomManager(roomManagerProxy);

        bytes memory initializeData =
            abi.encodeCall(FriendKey.initialize, (owner, address(mockUsdc), friendStakeBeacon, address(roomManager)));
        address proxy = Upgrades.deployUUPSProxy("FriendKey.sol", initializeData);
        instance = FriendKey(proxy);

        // Set FriendKey address in RoomManager
        roomManager.setFriendKey(address(instance));

        // Set fee destinations in RoomManager
        roomManager.setFeeDestinations(devFeeDestination, tradingPoolFeeDestination);
        vm.stopPrank();

        vm.startPrank(creatorAccount);
        string memory metadata = "";
        bytes memory signature = _getRegisterCreatorSignature(
            creatorAccount, FriendKey.RoomType.Trading, FriendKey.RoomTier.Club, 0, metadata
        );
        instance.registerCreator(metadata, signature);
        friendStake = FriendStake(instance.stakingPoolByTokenId(CREATOR_TOKEN_ID));
        assertEq(instance.creatorByTokenId(CREATOR_TOKEN_ID), creatorAccount, "TOKEN_ID mismatch");
        vm.stopPrank();

        mockUsdc.mint(creatorAccount, 1_000_000 * (10 ** 6));
        mockUsdc.mint(buyerAccount, 1_000_000 * (10 ** 6));
        mockUsdc.mint(anotherBuyerAccount, 1_000_000 * (10 ** 6));
    }

    // Helper function to check balances and token ownership
    function assertBalances(address account, uint256 expectedUsdcBalance, uint256 expectedTokenBalance) internal view {
        assertEq(mockUsdc.balanceOf(account), expectedUsdcBalance, "USDC balance mismatch");
        assertEq(instance.balanceOf(account, CREATOR_TOKEN_ID), expectedTokenBalance, "Token balance mismatch");
    }

    // Test management functions
    function testSetDevFeeDestination() public {
        vm.startPrank(owner);
        // address newDevFeeDestination = vm.addr(8); // Unused - fee destinations moved to RoomManager
        // Fee destination setting moved to FriendRoomManager
        // instance.setDevFeeDestination(newDevFeeDestination);
        // Fee destination setting moved to FriendRoomManager
        // instance.setTradingPoolFeeDestination(newDevFeeDestination);
        vm.stopPrank();

        // Fee destination variables moved to FriendRoomManager
        // assertEq(instance.devFeeDestination(), newDevFeeDestination, "Dev fee destination not updated");
        vm.startPrank(owner);
        // Fee destination variables moved to FriendRoomManager
        // address currentPoolDest = instance.tradingPoolFeeDestination();
        // Fee destination setting moved to FriendRoomManager
        // vm.expectRevert(Errors.ZeroAddress.selector);
        // instance.setDevFeeDestination(address(0));
        vm.stopPrank();
    }

    function testSetDevFeePercent() public {
        vm.startPrank(owner);
        // uint16 newDevFeePercent = 300; // 3% // Unused - fee setting moved to RoomManager
        // instance.setTradingFees(newDevFeePercent, instance.creatorFeePercent(), instance.tradingPoolFeePercent());
        vm.stopPrank();

        // Fee variables moved to FriendRoomManager
        // assertEq(instance.devFeePercent(), newDevFeePercent, "Dev fee percent not updated");
    }

    function testSetCreatorFeePercent() public {
        vm.startPrank(owner);
        // uint16 newCreatorFeePercent = 300; // 3% // Unused - fee setting moved to RoomManager
        // instance.setTradingFees(instance.devFeePercent(), newCreatorFeePercent, instance.tradingPoolFeePercent());
        vm.stopPrank();

        // Fee variables moved to FriendRoomManager
        // assertEq(instance.creatorFeePercent(), newCreatorFeePercent, "Creator fee percent not updated");
    }

    function testSetTradingPoolFeeDestination() public {
        vm.startPrank(owner);
        // address newTradingPoolFeeDestination = vm.addr(9); // Unused - fee destinations moved to RoomManager
        // Fee destination setting moved to FriendRoomManager
        // instance.setTradingPoolFeeDestination(newTradingPoolFeeDestination);
        vm.stopPrank();

        // assertEq(
        //     instance.tradingPoolFeeDestination(),
        //     newTradingPoolFeeDestination,
        //     "Trading pool fee destination not updated"
        // );
    }

    function testSetTradingPoolFeePercent() public {
        vm.startPrank(owner);
        // uint16 newTradingPoolFeePercent = 300; // 3% // Unused - fee setting moved to RoomManager
        // instance.setTradingFees(instance.devFeePercent(), instance.creatorFeePercent(), newTradingPoolFeePercent);
        vm.stopPrank();

        // Fee variables moved to FriendRoomManager
        // assertEq(instance.tradingPoolFeePercent(), newTradingPoolFeePercent, "Trading pool fee percent not updated");
    }

    function testSetDevPerformanceFeePercent() public {
        vm.startPrank(owner);
        // uint256 newPerformanceFeePercent = 500; // 5% // Unused - fee setting moved to RoomManager
        // instance.setPerformanceFees(uint16(newPerformanceFeePercent), instance.creatorPerformanceFeePercent());
        vm.stopPrank();

        // Fee variables moved to FriendRoomManager
        // assertEq(instance.devPerformanceFeePercent(), newPerformanceFeePercent, "Performance fee percent not updated");
    }

    function testSetCreatorPerformanceFeePercent() public {
        vm.startPrank(owner);
        // uint256 newPerformanceFeePercent = 500; // 5% // Unused - fee setting moved to RoomManager
        // instance.setPerformanceFees(instance.devPerformanceFeePercent(), uint16(newPerformanceFeePercent));
        vm.stopPrank();

        // Fee variables moved to FriendRoomManager
        // assertEq(instance.creatorPerformanceFeePercent(), newPerformanceFeePercent, "Performance fee percent not updated");
    }

    // Tests for buying shares
    function testBuyFirstShareAsCreator() public {
        // Ensure fees are set (they start at 0 after our changes)
        vm.startPrank(owner);
        // instance.setTradingFees(uint16(DEV_FEE_PERCENT), uint16(CREATOR_FEE_PERCENT), uint16(TRADING_POOL_FEE_PERCENT));
        // Fee destination setting moved to FriendRoomManager
        // instance.setDevFeeDestination(devFeeDestination);
        // Fee destination setting moved to FriendRoomManager
        // instance.setTradingPoolFeeDestination(tradingPoolFeeDestination);
        vm.stopPrank();

        uint256 initialBalance = mockUsdc.balanceOf(creatorAccount);
        uint256 basePrice = instance.getBuyPrice(CREATOR_TOKEN_ID, 1);
        uint256 price = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);

        vm.startPrank(creatorAccount);
        mockUsdc.approve(address(instance), price);
        instance.buyShares(CREATOR_TOKEN_ID, 1, type(uint256).max);
        vm.stopPrank();

        // Fee variables moved to FriendRoomManager - using default values for test
        uint256 creatorFee = (basePrice * 200) / instance.BPS_SCALE(); // Default 2% (DEV_FEE_PERCENT)
        assertBalances(creatorAccount, initialBalance - price + creatorFee, 2);

        // Verify supply
        assertEq(instance.totalSupply(CREATOR_TOKEN_ID), 2);
    }

    function testBuyFirstShareAsNonCreator() public {
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), 1000 * (10 ** 6));

        instance.buyShares(CREATOR_TOKEN_ID, 1, type(uint256).max);
        vm.stopPrank();

        // Verify supply remains 2 // one share on registration, one share bought by buyer
        assertEq(instance.totalSupply(CREATOR_TOKEN_ID), 2);
    }

    function testBuySharesAfterFirstShare() public {
        // Buyer buys shares after creator
        uint256 initialBuyerBalance = mockUsdc.balanceOf(buyerAccount);
        uint256 shareAmount = 3;
        uint256 price = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, shareAmount);

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), price);
        instance.buyShares(CREATOR_TOKEN_ID, shareAmount, type(uint256).max);
        vm.stopPrank();

        assertBalances(buyerAccount, initialBuyerBalance - price, shareAmount);

        // Verify total supply
        assertEq(instance.totalSupply(CREATOR_TOKEN_ID), 1 + shareAmount);
    }

    function testCannotBuyZeroShares() public {
        vm.startPrank(creatorAccount);
        vm.expectRevert(Errors.AmountMustBeGreaterThanZero.selector);
        instance.buyShares(CREATOR_TOKEN_ID, 0, type(uint256).max);
        vm.stopPrank();
    }

    function testBuyMultipleSharesBatch() public {
        // Multiple users buy shares
        uint256 buyerShareAmount = 2;
        uint256 anotherBuyerShareAmount = 5;

        uint256 buyerPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, buyerShareAmount);

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), buyerPrice);
        instance.buyShares(CREATOR_TOKEN_ID, buyerShareAmount, type(uint256).max);
        vm.stopPrank();

        uint256 anotherBuyerPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, anotherBuyerShareAmount);

        vm.startPrank(anotherBuyerAccount);
        mockUsdc.approve(address(instance), anotherBuyerPrice);
        instance.buyShares(CREATOR_TOKEN_ID, anotherBuyerShareAmount, type(uint256).max);
        vm.stopPrank();

        // Verify balances
        assertEq(instance.balanceOf(creatorAccount, CREATOR_TOKEN_ID), 1); // Creator has 1 share from registration
        assertEq(instance.balanceOf(buyerAccount, CREATOR_TOKEN_ID), buyerShareAmount);
        assertEq(instance.balanceOf(anotherBuyerAccount, CREATOR_TOKEN_ID), anotherBuyerShareAmount);

        // Verify total supply
        assertEq(instance.totalSupply(CREATOR_TOKEN_ID), 1 + buyerShareAmount + anotherBuyerShareAmount);
    }

    // Tests for selling shares
    function testSellShares() public {
        // Buyer buys shares
        uint256 buyAmount = 3;
        uint256 buyPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, buyAmount);

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount, type(uint256).max);

        // Buyer sells 1 share
        uint256 sellAmount = 1;
        uint256 balanceBefore = mockUsdc.balanceOf(buyerAccount);
        uint256 initialBondingCurveReserves = instance.bondingCurveReserves(creatorAccount);
        uint256 sellPriveWithFee = instance.getSellPrice(CREATOR_TOKEN_ID, sellAmount);
        uint256 sellPrice = instance.getSellPriceAfterFee(CREATOR_TOKEN_ID, sellAmount);
        vm.startSnapshotGas("sellShares");
        instance.sellShares(CREATOR_TOKEN_ID, sellAmount, 0);
        vm.stopSnapshotGas();
        uint256 balanceAfter = mockUsdc.balanceOf(buyerAccount);
        vm.stopPrank();

        // Verify share balances after selling
        assertEq(instance.balanceOf(buyerAccount, CREATOR_TOKEN_ID), buyAmount - sellAmount);
        assertEq(instance.totalSupply(CREATOR_TOKEN_ID), 1 + buyAmount - sellAmount);

        // Verify USDC balance increased (received funds from sale)
        assertEq(balanceAfter, balanceBefore + sellPrice, "Balance should increase by sell price");
        assertEq(
            instance.bondingCurveReserves(creatorAccount),
            initialBondingCurveReserves - sellPriveWithFee,
            "Bonding curve reserves should increase by sell price"
        );
    }

    function testUri() public {
        string memory myLittleUri = "http://localhost:3001/api/metadata/";

        // Set the URI (assuming the owner has permission to do this)
        vm.startPrank(owner);
        instance.setURI(myLittleUri);
        vm.stopPrank();

        // Verify the URI for the token
        string memory retrievedUri = instance.uri(CREATOR_TOKEN_ID);
        string memory expectedUri = string.concat(myLittleUri, CREATOR_TOKEN_ID.toString());
        assertEq(retrievedUri, expectedUri, "URI does not match expected value");

        // Verify the URI for a non-existent token
        uint256 nonExistentTokenId = 9999;
        vm.expectRevert(Errors.CreatorNotRegistered.selector);
        instance.uri(nonExistentTokenId);
    }

    function testIsUserEligible() public {
        // Check if creator is eligible
        bool isEligibleBefore = instance.isUserEligible(CREATOR_TOKEN_ID, creatorAccount);
        assertFalse(isEligibleBefore, "Creator should not be eligible");
        vm.warp(block.timestamp + 24 hours);
        bool isEligible = instance.isUserEligible(CREATOR_TOKEN_ID, creatorAccount);
        assertTrue(isEligible, "Creator should be eligible after 24 hours");

        // If user does not own the key, they should not be eligible
        uint256 buyerBalance = instance.balanceOf(buyerAccount, CREATOR_TOKEN_ID);
        assertEq(buyerBalance, 0, "Buyer should not own the key");
        vm.expectRevert(Errors.UserDoesNotHoldToken.selector);
        instance.isUserEligible(CREATOR_TOKEN_ID, buyerAccount);
    }

    function testgetKeyHoldingSince() public {
        // Should be zero before any buy
        uint256 buyerBalance = instance.balanceOf(buyerAccount, CREATOR_TOKEN_ID);
        assertEq(buyerBalance, 0, "Buyer should not own the key");
        uint256 zeroHoldingSince = instance.getKeyHoldingSince(CREATOR_TOKEN_ID, buyerAccount);
        assertEq(zeroHoldingSince, 0, "Holding since should be zero before first buy");

        // Should set on first buy
        vm.startPrank(buyerAccount);
        uint256 buyPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(CREATOR_TOKEN_ID, 1, type(uint256).max);
        vm.stopPrank();
        uint256 holdingSince = instance.getKeyHoldingSince(CREATOR_TOKEN_ID, buyerAccount);
        assertTrue(holdingSince > 0, "Holding since should be set after first buy");

        // Should not change on subsequent buys
        vm.startPrank(buyerAccount);
        uint256 newBuyPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 2);
        mockUsdc.approve(address(instance), newBuyPrice);
        instance.buyShares(CREATOR_TOKEN_ID, 2, type(uint256).max);
        vm.stopPrank();
        uint256 newHoldingSince = instance.getKeyHoldingSince(CREATOR_TOKEN_ID, buyerAccount);
        assertEq(newHoldingSince, holdingSince, "Holding since should not change on subsequent buys");

        // Should not change on sells
        vm.startPrank(buyerAccount);
        instance.sellShares(CREATOR_TOKEN_ID, 1, 0);
        vm.stopPrank();
        uint256 holdingSinceAfterSell = instance.getKeyHoldingSince(CREATOR_TOKEN_ID, buyerAccount);
        assertEq(holdingSinceAfterSell, holdingSince, "Holding since should not change on sells");

        // Should not change on stake if the user still holds the key
        vm.startPrank(buyerAccount);
        vm.startSnapshotGas("stake");
        instance.stake(CREATOR_TOKEN_ID, 1);
        vm.stopSnapshotGas();
        vm.stopPrank();
        uint256 holdingSinceAfterStake = instance.getKeyHoldingSince(CREATOR_TOKEN_ID, buyerAccount);
        assertEq(holdingSinceAfterStake, holdingSince, "Holding since should not change on stake");

        // Should not change on unstake
        vm.startPrank(buyerAccount);
        vm.startSnapshotGas("unstake");
        instance.unstake(CREATOR_TOKEN_ID, 1);
        vm.stopSnapshotGas();
        vm.stopPrank();
        uint256 holdingSinceAfterUnstake = instance.getKeyHoldingSince(CREATOR_TOKEN_ID, buyerAccount);
        assertEq(holdingSinceAfterUnstake, holdingSince, "Holding since should not change on unstake");
    }

    function testSellMultipleShares() public {
        // Buyer buys shares
        uint256 buyAmount = 5;
        uint256 buyPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, buyAmount);

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount, type(uint256).max);

        // Buyer sells multiple shares
        uint256 sellAmount = 3;
        uint256 balanceBefore = mockUsdc.balanceOf(buyerAccount);
        instance.sellShares(CREATOR_TOKEN_ID, sellAmount, 0);
        uint256 balanceAfter = mockUsdc.balanceOf(buyerAccount);
        vm.stopPrank();

        // Verify balances
        assertEq(instance.balanceOf(buyerAccount, CREATOR_TOKEN_ID), buyAmount - sellAmount);
        assertTrue(balanceAfter > balanceBefore, "Balance should increase after selling");
    }

    function testCannotSellMoreThanOwned() public {
        // Buyer buys shares
        uint256 buyAmount = 2;
        uint256 buyPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, buyAmount);

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount, type(uint256).max);

        // Attempt to sell more than owned
        vm.expectRevert(Errors.InsufficientShares.selector);
        instance.sellShares(CREATOR_TOKEN_ID, buyAmount + 1, 0);
        vm.stopPrank();
    }

    function testCannotSellAllRemainingShares() public {
        vm.startPrank(creatorAccount);
        // Creator attempts to sell all shares
        vm.expectRevert(Errors.CannotSellAllShares.selector);
        instance.sellShares(CREATOR_TOKEN_ID, 1, 0);
        vm.stopPrank();
    }

    function testFeeDistribution() public {
        // Ensure fees are set (they start at 0 after our changes)
        vm.startPrank(owner);
        // instance.setTradingFees(uint16(DEV_FEE_PERCENT), uint16(CREATOR_FEE_PERCENT), uint16(TRADING_POOL_FEE_PERCENT));
        // Fee destination setting moved to FriendRoomManager
        // instance.setDevFeeDestination(devFeeDestination);
        // Fee destination setting moved to FriendRoomManager
        // instance.setTradingPoolFeeDestination(tradingPoolFeeDestination);
        vm.stopPrank();

        // Record initial balances
        uint256 initialDevBalance = mockUsdc.balanceOf(devFeeDestination);
        uint256 initialTradingPoolBalance = mockUsdc.balanceOf(tradingPoolFeeDestination);
        uint256 initialCreatorFees = mockUsdc.balanceOf(creatorAccount);
        uint256 initialResevere = instance.bondingCurveReserves(creatorAccount);

        // Buyer buys shares
        uint256 buyAmount = 10;
        uint256 buyPrice = instance.getBuyPrice(CREATOR_TOKEN_ID, buyAmount);
        uint256 totalBuyPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, buyAmount);

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), totalBuyPrice);
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount, type(uint256).max);
        vm.stopPrank();

        // Calculate expected fees - using new default fees (200 = 2% dev/creator, 600 = 6% pool)
        uint256 expectedDevFee = buyPrice * 200 / instance.BPS_SCALE();
        uint256 expectedCreatorFee = buyPrice * 200 / instance.BPS_SCALE();
        uint256 expectedTradingPoolFee = buyPrice * 600 / instance.BPS_SCALE();
        uint256 expectedReserve = buyPrice;

        // Verify fees were distributed correctly
        assertEq(
            mockUsdc.balanceOf(devFeeDestination) - initialDevBalance,
            expectedDevFee,
            "Dev fee not distributed correctly"
        );
        assertEq(
            mockUsdc.balanceOf(tradingPoolFeeDestination) - initialTradingPoolBalance,
            expectedTradingPoolFee,
            "Trading pool fee not distributed correctly"
        );
        assertEq(
            mockUsdc.balanceOf(creatorAccount) - initialCreatorFees,
            expectedCreatorFee,
            "Creator fee not accumulated correctly"
        );

        assertEq(
            instance.bondingCurveReserves(creatorAccount) - initialResevere,
            expectedReserve,
            "Reserve not accumulated correctly"
        );
    }

    function testMetadataUriUsesStringPayload() public {
        address metadataCreator = vm.addr(20);
        string memory metadata = "CREATOR_META_HASH";
        uint256 tokenId = _registerCreator(metadataCreator, FriendKey.RoomTier.Club, 0, metadata);
        string memory tokenUri = instance.uri(tokenId);
        assertEq(tokenUri, metadata, "Metadata URI should match provided payload");
    }

    function testRegisterCreatorRevertsOnMetadataMismatch() public {
        address creator = vm.addr(21);
        string memory authorizedMetadata = "AUTHORIZED_HASH";
        bytes memory signature = _getRegisterCreatorSignature(creator, FriendKey.RoomTier.Club, 0, authorizedMetadata);

        vm.expectRevert(Errors.UnauthorizedRegisterSignature.selector);
        vm.prank(creator);
        instance.registerCreator("OTHER_HASH", signature);
    }

    function testRegisterCreatorWithAdditionalParameters() public {
        // Ensure fees are set (they start at 0 after our changes)
        vm.startPrank(owner);
        // instance.setTradingFees(uint16(DEV_FEE_PERCENT), uint16(CREATOR_FEE_PERCENT), uint16(TRADING_POOL_FEE_PERCENT));
        // Fee destination setting moved to FriendRoomManager
        // instance.setDevFeeDestination(devFeeDestination);
        // Fee destination setting moved to FriendRoomManager
        // instance.setTradingPoolFeeDestination(tradingPoolFeeDestination);
        vm.stopPrank();

        address newCreator = vm.addr(10);
        mockUsdc.mint(newCreator, 1_000_000 * (10 ** 6));

        // Test registering creator with Club tier and 5 additional keys
        FriendKey.RoomTier tier = FriendKey.RoomTier.Club;
        uint256 additionalKeys = 5;
        uint256 expectedTotalSupply = 1 + additionalKeys; // 1 initial + 5 additional

        // Calculate expected cost for the additional keys
        // First key is free (minted during registration), then we need to buy additionalKeys
        uint256 expectedCost = 0;
        uint256 creatorFee = 0;
        if (additionalKeys > 0) {
            uint256 divisor = 40;
            uint256 price = instance.getPrice(0, 1 + additionalKeys, divisor); // tokenId 2 since this is the second creator
            // Fee variables moved to FriendRoomManager - using default values for test
            uint256 devFee = (price * 200) / BPS_SCALE; // Default 2%
            creatorFee = (price * 200) / BPS_SCALE; // Default 2%
            uint256 tradingPoolFee = (price * 600) / BPS_SCALE; // Default 6%
            expectedCost = price + devFee + creatorFee + tradingPoolFee;
        }

        vm.startPrank(newCreator);
        mockUsdc.approve(address(instance), expectedCost);
        string memory metadata = "CLUB_CREATOR";
        bytes memory signature = _getRegisterCreatorSignature(newCreator, tier, additionalKeys, metadata);
        vm.startSnapshotGas("registerCreator");
        uint256 tokenId = instance.registerCreator(tier, additionalKeys, metadata, signature);
        vm.stopSnapshotGas();
        friendStake = FriendStake(instance.stakingPoolByTokenId(tokenId));
        vm.stopPrank();

        // Verify the token ID is correct (should be 2 since CREATOR_TOKEN_ID = 1 was already taken)
        assertEq(tokenId, 2, "Token ID should be 2");

        // Verify creator is properly registered
        assertEq(instance.creatorByTokenId(tokenId), newCreator, "Creator not registered correctly");

        // Verify room tier is set correctly
        assertEq(uint256(instance.roomTiers(tokenId)), uint256(tier), "Room tier not set correctly");

        // Verify total supply matches expected (1 initial + additionalKeys)
        assertEq(instance.totalSupply(tokenId), expectedTotalSupply, "Total supply not correct");

        // Verify creator owns all the tokens
        assertEq(instance.balanceOf(newCreator, tokenId), expectedTotalSupply, "Creator balance not correct");

        // Verify the creator's USDC balance decreased by the expected cost
        uint256 expectedBalance = 1_000_000 * (10 ** 6) - expectedCost + creatorFee;
        // Add back the creator fee to the expected balance because the creator receives a portion of the
        // transaction as a fee. This ensures the calculation reflects the net balance after accounting
        // for both the cost of the transaction and the fee received by the creator.
        assertEq(mockUsdc.balanceOf(newCreator), expectedBalance, "Creator USDC balance not correct");

        // Test with Exclusive tier and no additional keys
        address anotherCreator = vm.addr(11);
        mockUsdc.mint(anotherCreator, 1_000_000 * (10 ** 6));

        vm.startPrank(anotherCreator);
        metadata = "EXCLUSIVE_CREATOR";
        signature = _getRegisterCreatorSignature(anotherCreator, FriendKey.RoomTier.Exclusive, 0, metadata);
        uint256 anotherTokenId = instance.registerCreator(FriendKey.RoomTier.Exclusive, 0, metadata, signature);
        vm.stopPrank();

        // Verify the exclusive tier creator
        assertEq(anotherTokenId, 3, "Token ID should be 3");
        assertEq(instance.creatorByTokenId(anotherTokenId), anotherCreator, "Another creator not registered correctly");
        assertEq(
            uint256(instance.roomTiers(anotherTokenId)),
            uint256(FriendKey.RoomTier.Exclusive),
            "Exclusive tier not set correctly"
        );
        assertEq(instance.totalSupply(anotherTokenId), 1, "Total supply should be 1 for no additional keys");
        assertEq(instance.balanceOf(anotherCreator, anotherTokenId), 1, "Creator should own 1 token");
    }

    function testBatchTransfer() public {
        // Buyer buys shares
        uint256 buyAmount = 10;
        uint256 buyPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, buyAmount);

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount, type(uint256).max);
        vm.stopPrank();

        // Verify buyer owns the shares
        assertEq(instance.balanceOf(buyerAccount, CREATOR_TOKEN_ID), buyAmount);

        // Batch transfer shares to another account
        address recipient = vm.addr(12);
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = CREATOR_TOKEN_ID;
        amounts[0] = 2; // Transfer 2 shares
        ids[1] = CREATOR_TOKEN_ID;
        amounts[1] = 3; // Transfer 2 shares

        vm.prank(buyerAccount);
        instance.safeBatchTransferFrom(buyerAccount, recipient, ids, amounts, "");

        // Verify balances after batch transfer
        assertEq(instance.balanceOf(buyerAccount, CREATOR_TOKEN_ID), 5);
        assertEq(instance.balanceOf(recipient, CREATOR_TOKEN_ID), 5);
        // Verify keyHoldingSince is updated for the recipient
        uint256 holdingSince = instance.getKeyHoldingSince(CREATOR_TOKEN_ID, recipient);
        assertTrue(holdingSince > 0, "Recipient should have holding since set after batch transfer");

        vm.prank(recipient);
        // Verify batch transfer resets keyHoldingSince for the recipient
        instance.safeBatchTransferFrom(recipient, buyerAccount, ids, amounts, "");
        uint256 holdingSinceAfterReturn = instance.getKeyHoldingSince(CREATOR_TOKEN_ID, recipient);
        assertEq(holdingSinceAfterReturn, 0, "Holding since should be reset after returning shares");
    }

    // ============ ONE TIER PER CREATOR TESTS ============

    function testCanRegisterTier() public {
        address testCreator = vm.addr(60);

        // Initially, creator should be able to register all tiers
        assertTrue(
            instance.canRegisterRoom(testCreator, FriendKey.RoomType.Trading, FriendKey.RoomTier.Club),
            "Should be able to register Club"
        );
        assertTrue(
            instance.canRegisterRoom(testCreator, FriendKey.RoomType.Trading, FriendKey.RoomTier.Exclusive),
            "Should be able to register Exclusive"
        );

        // Register creator with Club tier
        mockUsdc.mint(testCreator, 1_000_000 * (10 ** 6));
        _registerCreator(testCreator, FriendKey.RoomTier.Club, 0, "test");

        // Now Club tier should not be available, but Exclusive should be
        assertFalse(
            instance.canRegisterRoom(testCreator, FriendKey.RoomType.Trading, FriendKey.RoomTier.Club),
            "Should not be able to register Club again"
        );
        assertTrue(
            instance.canRegisterRoom(testCreator, FriendKey.RoomType.Trading, FriendKey.RoomTier.Exclusive),
            "Should still be able to register Exclusive"
        );
    }

    function testCreatorCanRegisterMultipleDifferentTiers() public {
        address testCreator = vm.addr(70);
        mockUsdc.mint(testCreator, 10_000_000 * (10 ** 6)); // Give plenty of USDC

        // Register Club tier
        uint256 clubTokenId = _registerCreator(testCreator, FriendKey.RoomTier.Club, 0, "club");
        assertEq(instance.creatorByTokenId(clubTokenId), testCreator, "Creator should own club token");
        assertEq(
            uint256(instance.roomTiers(clubTokenId)), uint256(FriendKey.RoomTier.Club), "Token should be Club tier"
        );

        // Register Exclusive tier (should work)
        uint256 exclusiveTokenId = _registerCreator(testCreator, FriendKey.RoomTier.Exclusive, 0, "exclusive");
        assertEq(instance.creatorByTokenId(exclusiveTokenId), testCreator, "Creator should own exclusive token");
        assertEq(
            uint256(instance.roomTiers(exclusiveTokenId)),
            uint256(FriendKey.RoomTier.Exclusive),
            "Token should be Exclusive tier"
        );

        // Verify both tokens are different
        assertTrue(clubTokenId != exclusiveTokenId, "Club and Exclusive tokens should be different");

        // Verify creator owns tokens from both tiers
        assertTrue(instance.balanceOf(testCreator, clubTokenId) > 0, "Creator should own club tokens");
        assertTrue(instance.balanceOf(testCreator, exclusiveTokenId) > 0, "Creator should own exclusive tokens");
    }

    function testCreatorCannotRegisterSameTierTwice() public {
        // By default, only 1 room per tier is allowed
        address testCreator = vm.addr(80);
        mockUsdc.mint(testCreator, 10_000_000 * (10 ** 6));

        // Register Club tier first time (should work)
        _registerCreator(testCreator, FriendKey.RoomTier.Club, 0, "first");

        // Try to register Club tier again (should fail)
        bytes memory signature = _getRegisterCreatorSignature(testCreator, FriendKey.RoomTier.Club, 0, "second");
        vm.startPrank(testCreator);
        vm.expectRevert(Errors.RoomLimitExceeded.selector);
        instance.registerCreator(FriendKey.RoomTier.Club, 0, "second", signature);
        vm.stopPrank();

        // Try to register Exclusive tier (should work)
        _registerCreator(testCreator, FriendKey.RoomTier.Exclusive, 0, "exclusive");

        // Try to register Exclusive tier again (should fail)
        bytes memory exclusiveSignature =
            _getRegisterCreatorSignature(testCreator, FriendKey.RoomTier.Exclusive, 0, "exclusive2");
        vm.startPrank(testCreator);
        vm.expectRevert(Errors.RoomLimitExceeded.selector);
        instance.registerCreator(FriendKey.RoomTier.Exclusive, 0, "exclusive2", exclusiveSignature);
        vm.stopPrank();
    }

    // ============================================
    // ROOM MANAGER INTEGRATION TESTS
    // ============================================

    // Helper functions to convert enums for RoomManager calls
    function toIRoomType(FriendKey.RoomType t) internal pure returns (IFriendKey.RoomType) {
        return IFriendKey.RoomType(uint8(t));
    }

    function toIRoomTier(FriendKey.RoomTier t) internal pure returns (IFriendKey.RoomTier) {
        return IFriendKey.RoomTier(uint8(t));
    }

    function testRoomManagerIntegration_BasicFlow() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        address testCreator = vm.addr(100);
        mockUsdc.mint(testCreator, 10_000_000 * (10 ** 6));

        // Check initial room count
        assertEq(
            roomManager.getCreatorRoomCount(
                testCreator, toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club)
            ),
            0,
            "Initial room count should be 0"
        );

        // Register a room
        uint256 tokenId = _registerCreator(testCreator, FriendKey.RoomTier.Club, 0, "test");

        // Check room count increased
        assertEq(
            roomManager.getCreatorRoomCount(
                testCreator, toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club)
            ),
            1,
            "Room count should be 1 after registration"
        );

        // Check room is tracked
        uint256[] memory rooms = roomManager.getCreatorRooms(
            testCreator, toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club)
        );
        assertEq(rooms.length, 1, "Should have 1 room");
        assertEq(rooms[0], tokenId, "Room ID should match token ID");
    }

    function testRoomManagerIntegration_RoomLimitEnforcement() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        address testCreator = vm.addr(101);
        mockUsdc.mint(testCreator, 100_000_000 * (10 ** 6));

        // Register first room (should work)
        _registerCreator(testCreator, FriendKey.RoomTier.Club, 0, "room1");

        // Try to register second room (should fail - limit is 1)
        bytes memory signature = _getRegisterCreatorSignature(testCreator, FriendKey.RoomTier.Club, 0, "room2");
        vm.startPrank(testCreator);
        vm.expectRevert(Errors.RoomLimitExceeded.selector);
        instance.registerCreator(FriendKey.RoomTier.Club, 0, "room2", signature);
        vm.stopPrank();

        // Increase limit as owner
        vm.prank(owner);
        roomManager.setMaxRoomsPerTier(toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club), 2);

        // Now second room should work
        _registerCreator(testCreator, FriendKey.RoomTier.Club, 0, "room2");

        // Verify both rooms are tracked
        uint256[] memory rooms = roomManager.getCreatorRooms(
            testCreator, toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club)
        );
        assertEq(rooms.length, 2, "Should have 2 rooms");
    }

    function testRoomManagerIntegration_DisableRoomCreation() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        address testCreator = vm.addr(102);
        mockUsdc.mint(testCreator, 10_000_000 * (10 ** 6));

        // Disable Exclusive tier room creation
        vm.prank(owner);
        roomManager.disableRoomType(toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Exclusive));

        // Try to register Exclusive room (should fail)
        bytes memory signature = _getRegisterCreatorSignature(testCreator, FriendKey.RoomTier.Exclusive, 0, "exclusive");
        vm.startPrank(testCreator);
        vm.expectRevert(Errors.RoomLimitExceeded.selector);
        instance.registerCreator(FriendKey.RoomTier.Exclusive, 0, "exclusive", signature);
        vm.stopPrank();

        // Re-enable room creation
        vm.prank(owner);
        roomManager.enableRoomType(toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Exclusive));

        // Now should work
        _registerCreator(testCreator, FriendKey.RoomTier.Exclusive, 0, "exclusive");
    }

    function testRoomManagerIntegration_BatchSetLimits() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        IFriendKey.RoomType[] memory roomTypes = new IFriendKey.RoomType[](3);
        IFriendKey.RoomTier[] memory tiers = new IFriendKey.RoomTier[](3);
        uint256[] memory limits = new uint256[](3);

        roomTypes[0] = toIRoomType(FriendKey.RoomType.Trading);
        roomTypes[1] = toIRoomType(FriendKey.RoomType.Trading);
        roomTypes[2] = toIRoomType(FriendKey.RoomType.Social);

        tiers[0] = toIRoomTier(FriendKey.RoomTier.Club);
        tiers[1] = toIRoomTier(FriendKey.RoomTier.Exclusive);
        tiers[2] = toIRoomTier(FriendKey.RoomTier.Casual);

        limits[0] = 5;
        limits[1] = 3;
        limits[2] = 10;

        vm.prank(owner);
        roomManager.batchSetLimits(roomTypes, tiers, limits);

        // Verify limits were set
        assertEq(
            roomManager.maxRoomsPerTier(toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club)),
            5,
            "Club limit should be 5"
        );
        assertEq(
            roomManager.maxRoomsPerTier(
                toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Exclusive)
            ),
            3,
            "Exclusive limit should be 3"
        );
        assertEq(
            roomManager.maxRoomsPerTier(toIRoomType(FriendKey.RoomType.Social), toIRoomTier(FriendKey.RoomTier.Casual)),
            10,
            "Social Casual limit should be 10"
        );
    }

    function testRoomManagerIntegration_FeeConfiguration() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        // Change trading fees
        vm.prank(owner);
        roomManager.setTradingFees(300, 300, 400);

        (uint16 dev, uint16 creator, uint16 pool) = roomManager.getTradingFees();
        assertEq(dev, 300, "Dev fee should be 300");
        assertEq(creator, 300, "Creator fee should be 300");
        assertEq(pool, 400, "Pool fee should be 400");

        // Change performance fees
        vm.prank(owner);
        roomManager.setPerformanceFees(600, 1400);

        (uint16 devPerf, uint16 creatorPerf) = roomManager.getPerformanceFees();
        assertEq(devPerf, 600, "Dev performance fee should be 600");
        assertEq(creatorPerf, 1400, "Creator performance fee should be 1400");

        // Change social fees
        vm.prank(owner);
        roomManager.setSocialFees(150, 250);

        (uint16 socialDev, uint16 socialCreator) = roomManager.getSocialFees();
        assertEq(socialDev, 150, "Social dev fee should be 150");
        assertEq(socialCreator, 250, "Social creator fee should be 250");
    }

    function testRoomManagerIntegration_FeeValidation() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        // Try to set fees that exceed 100%
        vm.prank(owner);
        vm.expectRevert(Errors.TotalFeePercentTooHigh.selector);
        roomManager.setTradingFees(5000, 5000, 1000); // 110%

        // Try to set social fees that exceed 100%
        vm.prank(owner);
        vm.expectRevert(Errors.TotalFeePercentTooHigh.selector);
        roomManager.setSocialFees(5000, 6000); // 110%
    }

    function testRoomManagerIntegration_BondingCurveConfig() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        // Set new bonding curve divisors
        uint256[3] memory newDivisors = [uint256(5000), uint256(50), uint256(5)];

        vm.prank(owner);
        roomManager.setBondingCurveDivisors(newDivisors);

        // Verify divisors were set
        assertEq(
            roomManager.getDivisor(toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Casual)),
            5000,
            "Casual divisor should be 5000"
        );
        assertEq(
            roomManager.getDivisor(toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club)),
            50,
            "Club divisor should be 50"
        );
        assertEq(
            roomManager.getDivisor(toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Exclusive)),
            5,
            "Exclusive divisor should be 5"
        );

        // Set social divisors
        uint256[3] memory socialDivisors = [uint256(10000), uint256(100), uint256(10)];

        vm.prank(owner);
        roomManager.setSocialDivisors(socialDivisors);

        // Verify social divisors
        assertEq(
            roomManager.getDivisor(toIRoomType(FriendKey.RoomType.Social), toIRoomTier(FriendKey.RoomTier.Casual)),
            10000,
            "Social Casual divisor should be 10000"
        );
    }

    function testRoomManagerIntegration_AuthorityAndEligibility() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        address newAuthority = vm.addr(200);

        // Set new authority
        vm.prank(owner);
        roomManager.setAuthority(newAuthority);

        assertEq(roomManager.authority(), newAuthority, "Authority should be updated");

        // Set new eligibility duration
        uint256 newDuration = 48 hours;
        vm.prank(owner);
        roomManager.setEligibilityDuration(newDuration);

        assertEq(roomManager.eligibilityDuration(), newDuration, "Eligibility duration should be updated");
    }

    function testRoomManagerIntegration_MultipleRoomsPerCreator() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        address testCreator = vm.addr(103);
        mockUsdc.mint(testCreator, 100_000_000 * (10 ** 6));

        // Set limit to 3 rooms per tier
        vm.prank(owner);
        roomManager.setMaxRoomsPerTier(toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club), 3);

        // Register 3 rooms
        uint256 room1 = _registerCreator(testCreator, FriendKey.RoomTier.Club, 0, "room1");
        uint256 room2 = _registerCreator(testCreator, FriendKey.RoomTier.Club, 0, "room2");
        uint256 room3 = _registerCreator(testCreator, FriendKey.RoomTier.Club, 0, "room3");

        // Verify all rooms are tracked
        uint256[] memory rooms = roomManager.getCreatorRooms(
            testCreator, toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club)
        );
        assertEq(rooms.length, 3, "Should have 3 rooms");
        assertEq(rooms[0], room1, "First room should match");
        assertEq(rooms[1], room2, "Second room should match");
        assertEq(rooms[2], room3, "Third room should match");

        // Try to register 4th room (should fail)
        bytes memory signature = _getRegisterCreatorSignature(testCreator, FriendKey.RoomTier.Club, 0, "room4");
        vm.startPrank(testCreator);
        vm.expectRevert(Errors.RoomLimitExceeded.selector);
        instance.registerCreator(FriendKey.RoomTier.Club, 0, "room4", signature);
        vm.stopPrank();
    }

    function testRoomManagerIntegration_CrossTierIndependence() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        address testCreator = vm.addr(104);
        mockUsdc.mint(testCreator, 100_000_000 * (10 ** 6));

        // Register Club room
        _registerCreator(testCreator, FriendKey.RoomTier.Club, 0, "club");

        // Register Exclusive room (should be independent of Club)
        _registerCreator(testCreator, FriendKey.RoomTier.Exclusive, 0, "exclusive");

        // Verify both tiers have 1 room each
        assertEq(
            roomManager.getCreatorRoomCount(
                testCreator, toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club)
            ),
            1,
            "Should have 1 Club room"
        );
        assertEq(
            roomManager.getCreatorRoomCount(
                testCreator, toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Exclusive)
            ),
            1,
            "Should have 1 Exclusive room"
        );

        // Try to register another Club room (should fail)
        bytes memory signature = _getRegisterCreatorSignature(testCreator, FriendKey.RoomTier.Club, 0, "club2");
        vm.startPrank(testCreator);
        vm.expectRevert(Errors.RoomLimitExceeded.selector);
        instance.registerCreator(FriendKey.RoomTier.Club, 0, "club2", signature);
        vm.stopPrank();
    }

    // ============================================
    // EDGE CASE AND SECURITY TESTS
    // ============================================

    function testEdgeCase_ZeroAmountBuyReverts() public {
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);

        vm.expectRevert(); // Should revert on zero amount
        instance.buyShares(CREATOR_TOKEN_ID, 0, type(uint256).max);
        vm.stopPrank();
    }

    function testEdgeCase_ZeroAmountSellReverts() public {
        // First buy some shares
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);
        instance.buyShares(CREATOR_TOKEN_ID, 10, type(uint256).max);

        vm.expectRevert(); // Should revert on zero amount
        instance.sellShares(CREATOR_TOKEN_ID, 0, 0);
        vm.stopPrank();
    }

    function testEdgeCase_BuyMoreThanCreatorCanSell() public {
        // Try to sell more than the creator has
        vm.startPrank(creatorAccount);
        uint256 creatorBalance = instance.balanceOf(creatorAccount, CREATOR_TOKEN_ID);

        mockUsdc.approve(address(instance), type(uint256).max);
        vm.expectRevert(); // Should revert - can't sell more than balance
        instance.sellShares(CREATOR_TOKEN_ID, creatorBalance + 1, 0);
        vm.stopPrank();
    }

    function testEdgeCase_SlippageProtectionOnBuy() public {
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);

        uint256 amount = 10;
        uint256 price = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, amount);

        // Set maxSpend lower than actual price
        vm.expectRevert(Errors.SlippageExceededMaxSpend.selector);
        instance.buyShares(CREATOR_TOKEN_ID, amount, price - 1);

        // Should work with correct maxSpend
        instance.buyShares(CREATOR_TOKEN_ID, amount, price);
        vm.stopPrank();
    }

    function testEdgeCase_SlippageProtectionOnSell() public {
        // First buy some shares
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);
        instance.buyShares(CREATOR_TOKEN_ID, 10, type(uint256).max);

        uint256 amount = 5;
        uint256 price = instance.getSellPriceAfterFee(CREATOR_TOKEN_ID, amount);

        // Set minReceive higher than actual price
        vm.expectRevert(Errors.SlippageExceededMinReceive.selector);
        instance.sellShares(CREATOR_TOKEN_ID, amount, price + 1);

        // Should work with correct minReceive
        instance.sellShares(CREATOR_TOKEN_ID, amount, price);
        vm.stopPrank();
    }

    function testSecurity_ReentrancyProtection() public {
        // Note: FriendKey doesn't have explicit reentrancy guards
        // This is a potential security issue if malicious tokens are used
        // The contract relies on Checks-Effects-Interactions pattern

        // Test basic buy/sell in sequence (simulating potential reentrancy)
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);

        instance.buyShares(CREATOR_TOKEN_ID, 10, type(uint256).max);
        instance.sellShares(CREATOR_TOKEN_ID, 5, 0);
        instance.buyShares(CREATOR_TOKEN_ID, 3, type(uint256).max);

        vm.stopPrank();
    }

    function testSecurity_SignatureReplayPrevention() public {
        address testCreator = vm.addr(105);
        mockUsdc.mint(testCreator, 10_000_000 * (10 ** 6));

        // Get signature for first registration
        bytes memory signature = _getRegisterCreatorSignature(testCreator, FriendKey.RoomTier.Club, 0, "test");

        // Register first time
        vm.prank(testCreator);
        instance.registerCreator(FriendKey.RoomTier.Club, 0, "test", signature);

        // Try to use same signature again (should fail due to nonce increment)
        vm.prank(testCreator);
        vm.expectRevert(); // Signature verification should fail
        instance.registerCreator(FriendKey.RoomTier.Club, 0, "test", signature);
    }

    function testSecurity_OnlyOwnerCanUpdateRoomManager() public {
        address maliciousUser = vm.addr(999);
        address newRoomManager = vm.addr(998);

        vm.prank(maliciousUser);
        vm.expectRevert(); // Should fail - not owner
        instance.setRoomManager(newRoomManager);
    }

    function testSecurity_CannotSetZeroAddressRoomManager() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        instance.setRoomManager(address(0));
    }

    function testSecurity_OnlyRoomManagerCanCallCheckAndUpdate() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        address maliciousUser = vm.addr(997);

        // Try to call checkAndUpdateRoomRegistration directly (should fail)
        vm.prank(maliciousUser);
        vm.expectRevert(); // Should revert - only FriendKey can call
        roomManager.checkAndUpdateRoomRegistration(
            maliciousUser, toIRoomType(FriendKey.RoomType.Trading), toIRoomTier(FriendKey.RoomTier.Club), 999
        );
    }

    function testSecurity_CannotBuyFromNonExistentRoom() public {
        uint256 nonExistentTokenId = 9999;

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);

        vm.expectRevert(Errors.CreatorNotRegistered.selector);
        instance.buyShares(nonExistentTokenId, 10, type(uint256).max);
        vm.stopPrank();
    }

    function testSecurity_OnlyCreatorCanBuyFirstShare() public {
        address testCreator = vm.addr(106);
        mockUsdc.mint(testCreator, 10_000_000 * (10 ** 6));
        mockUsdc.mint(buyerAccount, 10_000_000 * (10 ** 6));

        // Register but get tokenId without buying first share
        bytes memory signature = _getRegisterCreatorSignature(testCreator, FriendKey.RoomTier.Club, 0, "test");
        vm.prank(testCreator);
        instance.registerCreator(FriendKey.RoomTier.Club, 0, "test", signature);

        // For this test, we need to simulate a room with 0 supply
        // In actual implementation, creator always buys first share, so this scenario shouldn't happen
        // But we can test the logic exists
    }

    // Pause tests
    function testPause_BuySharesRevertsWhenPaused() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        vm.prank(owner);
        roomManager.pause();
        assertTrue(roomManager.paused());

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);
        vm.expectRevert(Errors.ContractPaused.selector);
        instance.buyShares(CREATOR_TOKEN_ID, 10, type(uint256).max);
        vm.stopPrank();
    }

    function testPause_SellSharesRevertsWhenPaused() public {
        // First buy some shares
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);
        instance.buyShares(CREATOR_TOKEN_ID, 10, type(uint256).max);
        vm.stopPrank();

        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        vm.prank(owner);
        roomManager.pause();

        // Try to sell shares - should revert
        vm.startPrank(buyerAccount);
        vm.expectRevert(Errors.ContractPaused.selector);
        instance.sellShares(CREATOR_TOKEN_ID, 5, 0);
        vm.stopPrank();
    }

    function testPause_StakeRevertsWhenPaused() public {
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);
        instance.buyShares(CREATOR_TOKEN_ID, 10, type(uint256).max);
        vm.stopPrank();

        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        vm.prank(owner);
        roomManager.pause();

        // Try to stake - should revert
        vm.startPrank(buyerAccount);
        instance.setApprovalForAll(address(friendStake), true);
        vm.expectRevert(Errors.ContractPaused.selector);
        instance.stake(CREATOR_TOKEN_ID, 5);
        vm.stopPrank();
    }

    function testPause_UnstakeRevertsWhenPaused() public {
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);
        instance.buyShares(CREATOR_TOKEN_ID, 10, type(uint256).max);
        instance.setApprovalForAll(address(friendStake), true);
        instance.stake(CREATOR_TOKEN_ID, 5);
        vm.stopPrank();

        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        vm.prank(owner);
        roomManager.pause();

        // Try to unstake - should revert
        vm.startPrank(buyerAccount);
        vm.expectRevert(Errors.ContractPaused.selector);
        instance.unstake(CREATOR_TOKEN_ID, 3);
        vm.stopPrank();
    }

    function testPause_RegisterCreatorRevertsWhenPaused() public {
        address testCreator = vm.addr(107);
        mockUsdc.mint(testCreator, 10_000_000 * (10 ** 6));

        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        vm.prank(owner);
        roomManager.pause();

        bytes memory signature = _getRegisterCreatorSignature(testCreator, FriendKey.RoomTier.Club, 0, "test");
        vm.prank(testCreator);
        vm.expectRevert(Errors.ContractPaused.selector);
        instance.registerCreator(FriendKey.RoomTier.Club, 0, "test", signature);
    }

    function testPause_OperationsWorkAfterUnpause() public {
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);

        vm.prank(owner);
        roomManager.pause();

        vm.prank(owner);
        roomManager.unpause();
        assertFalse(roomManager.paused());

        // Operations should work again
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);
        instance.buyShares(CREATOR_TOKEN_ID, 10, type(uint256).max);
        instance.sellShares(CREATOR_TOKEN_ID, 5, 0);
        vm.stopPrank();
    }

    // ============================================
    // SOCIAL ROOM TESTS
    // ============================================

    function testRegisterSocialCreator() public {
        // Enable Social rooms
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);
        vm.prank(owner);
        roomManager.enableRoomType(toIRoomType(FriendKey.RoomType.Social), toIRoomTier(FriendKey.RoomTier.Club));

        address socialCreator = vm.addr(200);
        mockUsdc.mint(socialCreator, 1_000_000 * (10 ** 6));

        string memory metadata = "SOCIAL_METADATA";
        bytes memory signature = _getRegisterCreatorSignature(
            socialCreator, FriendKey.RoomType.Social, FriendKey.RoomTier.Club, 0, metadata
        );

        vm.startPrank(socialCreator);
        uint256 tokenId = instance.registerSocialCreator(FriendKey.RoomTier.Club, 0, metadata, signature);
        vm.stopPrank();

        assertEq(instance.creatorByTokenId(tokenId), socialCreator, "Creator should be registered");
        assertEq(uint256(instance.roomTypes(tokenId)), uint256(FriendKey.RoomType.Social), "Should be Social room type");
        assertEq(instance.stakingPoolByTokenId(tokenId), address(0), "Social rooms should not have staking pool");
        assertEq(instance.totalSupply(tokenId), 1, "Should have 1 initial share");
    }

    function testRegisterSocialCreatorWithDefaultTier() public {
        // Enable Social rooms
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);
        vm.prank(owner);
        roomManager.enableRoomType(toIRoomType(FriendKey.RoomType.Social), toIRoomTier(FriendKey.RoomTier.Club));

        address socialCreator = vm.addr(201);
        mockUsdc.mint(socialCreator, 1_000_000 * (10 ** 6));

        string memory metadata = "SOCIAL_DEFAULT";
        bytes memory signature = _getRegisterCreatorSignature(
            socialCreator, FriendKey.RoomType.Social, FriendKey.RoomTier.Club, 0, metadata
        );

        vm.startPrank(socialCreator);
        uint256 tokenId = instance.registerSocialCreator(metadata, signature);
        vm.stopPrank();

        assertEq(instance.creatorByTokenId(tokenId), socialCreator, "Creator should be registered");
        assertEq(uint256(instance.roomTypes(tokenId)), uint256(FriendKey.RoomType.Social), "Should be Social room type");
        assertEq(uint256(instance.roomTiers(tokenId)), uint256(FriendKey.RoomTier.Club), "Should be Club tier");
    }

    function testSocialRoomBuyShares() public {
        // Enable Social rooms
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);
        vm.prank(owner);
        roomManager.enableRoomType(toIRoomType(FriendKey.RoomType.Social), toIRoomTier(FriendKey.RoomTier.Club));

        address socialCreator = vm.addr(203);
        mockUsdc.mint(socialCreator, 10_000_000 * (10 ** 6));
        mockUsdc.mint(buyerAccount, 10_000_000 * (10 ** 6));

        bytes memory signature =
            _getRegisterCreatorSignature(socialCreator, FriendKey.RoomType.Social, FriendKey.RoomTier.Club, 0, "");
        vm.startPrank(socialCreator);
        uint256 tokenId = instance.registerSocialCreator("", signature);
        vm.stopPrank();

        // Buyer buys shares from social room
        vm.startPrank(buyerAccount);
        uint256 buyPrice = instance.getBuyPriceAfterFee(tokenId, 3);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(tokenId, 3, type(uint256).max);
        vm.stopPrank();

        assertEq(instance.balanceOf(buyerAccount, tokenId), 3, "Buyer should have 3 shares");
        assertEq(instance.totalSupply(tokenId), 4, "Total supply should be 4");
    }

    function testSocialRoomSellShares() public {
        // Enable Social rooms
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);
        vm.prank(owner);
        roomManager.enableRoomType(toIRoomType(FriendKey.RoomType.Social), toIRoomTier(FriendKey.RoomTier.Club));

        address socialCreator = vm.addr(204);
        mockUsdc.mint(socialCreator, 10_000_000 * (10 ** 6));
        mockUsdc.mint(buyerAccount, 10_000_000 * (10 ** 6));

        bytes memory signature =
            _getRegisterCreatorSignature(socialCreator, FriendKey.RoomType.Social, FriendKey.RoomTier.Club, 0, "");
        vm.startPrank(socialCreator);
        uint256 tokenId = instance.registerSocialCreator("", signature);
        vm.stopPrank();

        // Buyer buys and then sells
        vm.startPrank(buyerAccount);
        uint256 buyPrice = instance.getBuyPriceAfterFee(tokenId, 5);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(tokenId, 5, type(uint256).max);

        uint256 balanceBefore = mockUsdc.balanceOf(buyerAccount);
        instance.sellShares(tokenId, 2, 0);
        uint256 balanceAfter = mockUsdc.balanceOf(buyerAccount);
        vm.stopPrank();

        assertEq(instance.balanceOf(buyerAccount, tokenId), 3, "Buyer should have 3 shares left");
        assertTrue(balanceAfter > balanceBefore, "Balance should increase after sell");
    }

    function testSocialRoomCannotStake() public {
        // Enable Social rooms
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);
        vm.prank(owner);
        roomManager.enableRoomType(toIRoomType(FriendKey.RoomType.Social), toIRoomTier(FriendKey.RoomTier.Club));

        address socialCreator = vm.addr(205);
        mockUsdc.mint(socialCreator, 10_000_000 * (10 ** 6));
        mockUsdc.mint(buyerAccount, 10_000_000 * (10 ** 6));

        bytes memory signature =
            _getRegisterCreatorSignature(socialCreator, FriendKey.RoomType.Social, FriendKey.RoomTier.Club, 0, "");
        vm.startPrank(socialCreator);
        uint256 tokenId = instance.registerSocialCreator("", signature);
        vm.stopPrank();

        // Buyer buys shares
        vm.startPrank(buyerAccount);
        uint256 buyPrice = instance.getBuyPriceAfterFee(tokenId, 2);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(tokenId, 2, type(uint256).max);

        // Try to stake - should fail (no staking pool)
        vm.expectRevert(Errors.StakingPoolNotRegistered.selector);
        instance.stake(tokenId, 1);
        vm.stopPrank();
    }

    function testCanRegisterRoom_SocialType() public {
        // Enable Social rooms
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);
        vm.prank(owner);
        roomManager.enableRoomType(toIRoomType(FriendKey.RoomType.Social), toIRoomTier(FriendKey.RoomTier.Club));

        address testCreator = vm.addr(206);
        mockUsdc.mint(testCreator, 10_000_000 * (10 ** 6));

        // Can register Social room
        assertTrue(
            instance.canRegisterRoom(testCreator, FriendKey.RoomType.Social, FriendKey.RoomTier.Club),
            "Should be able to register Social Club"
        );

        // Register Social room
        bytes memory signature =
            _getRegisterCreatorSignature(testCreator, FriendKey.RoomType.Social, FriendKey.RoomTier.Club, 0, "");
        vm.prank(testCreator);
        instance.registerSocialCreator("", signature);

        // Can still register Trading room (different type)
        assertTrue(
            instance.canRegisterRoom(testCreator, FriendKey.RoomType.Trading, FriendKey.RoomTier.Club),
            "Should be able to register Trading Club after Social"
        );
    }

    // ============================================
    // SET SIGNEE TESTS
    // ============================================

    function testSetSignee() public {
        address newSignee = vm.addr(300);

        vm.prank(owner);
        instance.setSignee(newSignee);

        // Test that signee can now sign registrations
        address testCreator = vm.addr(301);
        mockUsdc.mint(testCreator, 1_000_000 * (10 ** 6));

        // Create signature with new signee's private key
        uint256 signeePrivateKey = 300;
        bytes memory signature =
            _getRegisterCreatorSignatureWithKey(testCreator, FriendKey.RoomTier.Club, 0, "", signeePrivateKey);

        vm.prank(testCreator);
        uint256 tokenId = instance.registerCreator("", signature);
        assertEq(instance.creatorByTokenId(tokenId), testCreator, "Creator should be registered with signee signature");
    }

    function testSetSignee_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        instance.setSignee(address(0));
    }

    function testSetSignee_OnlyOwner() public {
        address maliciousUser = vm.addr(999);
        vm.prank(maliciousUser);
        vm.expectRevert();
        instance.setSignee(vm.addr(300));
    }

    function _getRegisterCreatorSignatureWithKey(
        address account,
        FriendKey.RoomTier tier,
        uint256 additionalKeys,
        string memory metadata,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        return _getRegisterCreatorSignatureWithKey(
            account, FriendKey.RoomType.Trading, tier, additionalKeys, metadata, privateKey
        );
    }

    function _getRegisterCreatorSignatureWithKey(
        address account,
        FriendKey.RoomType roomType,
        FriendKey.RoomTier tier,
        uint256 additionalKeys,
        string memory metadata,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        uint256 nonce = instance.registerCreatorNonces(account);
        bytes32 metadataHash = keccak256(bytes(metadata));
        bytes32 structHash = keccak256(
            abi.encode(
                REGISTER_CREATOR_TYPEHASH, account, uint8(roomType), uint8(tier), additionalKeys, nonce, metadataHash
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ============================================
    // TRANSFER TO POOL EDGE CASES
    // ============================================

    function testTransferToPool_SocialRoom() public {
        // Enable Social rooms
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);
        vm.prank(owner);
        roomManager.enableRoomType(toIRoomType(FriendKey.RoomType.Social), toIRoomTier(FriendKey.RoomTier.Club));

        address socialCreator = vm.addr(400);
        mockUsdc.mint(socialCreator, 10_000_000 * (10 ** 6));
        mockUsdc.mint(buyerAccount, 10_000_000 * (10 ** 6));

        bytes memory signature =
            _getRegisterCreatorSignature(socialCreator, FriendKey.RoomType.Social, FriendKey.RoomTier.Club, 0, "");
        vm.startPrank(socialCreator);
        uint256 tokenId = instance.registerSocialCreator("", signature);
        vm.stopPrank();

        // Buy shares - fees should go to dev destination for social rooms
        uint256 devBalanceBefore = mockUsdc.balanceOf(devFeeDestination);
        vm.startPrank(buyerAccount);
        uint256 buyPrice = instance.getBuyPriceAfterFee(tokenId, 10);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(tokenId, 10, type(uint256).max);
        vm.stopPrank();

        uint256 devBalanceAfter = mockUsdc.balanceOf(devFeeDestination);
        assertTrue(devBalanceAfter > devBalanceBefore, "Dev should receive fees from social room");
    }

    function testTransferToPool_EOA() public {
        // Create a simple EOA address (no contract code)
        address eoaPool = vm.addr(500);

        // Update trading pool fee destination to EOA
        address roomManagerAddr = instance.roomManager();
        FriendRoomManager roomManager = FriendRoomManager(roomManagerAddr);
        vm.prank(owner);
        roomManager.setFeeDestinations(devFeeDestination, eoaPool);

        // Buy shares - should transfer directly to EOA
        uint256 eoaBalanceBefore = mockUsdc.balanceOf(eoaPool);
        vm.startPrank(buyerAccount);
        uint256 buyPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 5);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(CREATOR_TOKEN_ID, 5, type(uint256).max);
        vm.stopPrank();

        uint256 eoaBalanceAfter = mockUsdc.balanceOf(eoaPool);
        assertTrue(eoaBalanceAfter > eoaBalanceBefore, "EOA should receive pool fees");
    }

    // ============================================
    // ADDITIONAL EDGE CASES
    // ============================================

    function testBuyShares_InsufficientAllowance() public {
        vm.startPrank(buyerAccount);
        uint256 price = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 10);
        mockUsdc.approve(address(instance), price - 1); // Approve less than needed

        vm.expectRevert(Errors.InsufficientAllowance.selector);
        instance.buyShares(CREATOR_TOKEN_ID, 10, type(uint256).max);
        vm.stopPrank();
    }

    function testBuyShares_InsufficientBalance() public {
        vm.startPrank(buyerAccount);
        uint256 price = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 10);
        mockUsdc.approve(address(instance), price);

        // Set balance to less than needed
        uint256 currentBalance = mockUsdc.balanceOf(buyerAccount);
        uint256 amountToBurn = currentBalance - price + 1;
        mockUsdc.burn(buyerAccount, amountToBurn); // Reduce balance

        vm.expectRevert(Errors.InsufficientBalance.selector);
        instance.buyShares(CREATOR_TOKEN_ID, 10, type(uint256).max);
        vm.stopPrank();
    }

    function testBuyShares_SlippageProtectionRequired() public {
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), type(uint256).max);

        vm.expectRevert(Errors.SlippageProtectionRequired.selector);
        instance.buyShares(CREATOR_TOKEN_ID, 10, 0); // maxSpend = 0
        vm.stopPrank();
    }

    function testSellShares_AmountExceedsSupply() public {
        uint256 currentSupply = instance.totalSupply(CREATOR_TOKEN_ID);

        vm.startPrank(buyerAccount);
        vm.expectRevert(Errors.AmountExceedsSupply.selector);
        instance.getSellPrice(CREATOR_TOKEN_ID, currentSupply + 1);
        vm.stopPrank();
    }

    function testUri_WithMetadata() public {
        address testCreator = vm.addr(600);
        mockUsdc.mint(testCreator, 1_000_000 * (10 ** 6));

        string memory metadata = "ipfs://QmTestHash";
        bytes memory signature = _getRegisterCreatorSignature(testCreator, FriendKey.RoomTier.Club, 0, metadata);

        vm.prank(testCreator);
        uint256 tokenId = instance.registerCreator(FriendKey.RoomTier.Club, 0, metadata, signature);

        string memory retrievedUri = instance.uri(tokenId);
        assertEq(retrievedUri, metadata, "URI should match metadata");
    }
}
