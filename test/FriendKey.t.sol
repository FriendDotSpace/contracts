// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IFriendPool} from "src/interfaces/IFriendPool.sol";

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

    function setUp() public {
        owner = vm.addr(1);
        devFeeDestination = vm.addr(2);

        creatorAccount = vm.addr(5);
        buyerAccount = vm.addr(6);
        anotherBuyerAccount = vm.addr(7);

        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);

        MockPool pool = new MockPool(address(mockUsdc));
        tradingPoolFeeDestination = address(pool); //vm.addr(4);

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
                address(mockUsdc)
            )
        );
        address proxy = Upgrades.deployUUPSProxy("FriendKey.sol", initializeData);
        instance = FriendKey(proxy);
        vm.stopPrank();

        vm.startPrank(creatorAccount);
        // Register creator
        instance.registerCreator();
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

    // Tests for buying shares
    function testBuyFirstShareAsCreator() public {
        uint256 initialBalance = mockUsdc.balanceOf(creatorAccount);
        uint256 basePrice = instance.getBuyPrice(CREATOR_TOKEN_ID, 1);
        uint256 price = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 1);

        vm.startPrank(creatorAccount);
        mockUsdc.approve(address(instance), price);
        instance.buyShares(CREATOR_TOKEN_ID, 1);
        vm.stopPrank();

        uint256 creatorFee = (basePrice * CREATOR_FEE_PERCENT) / instance.BPS_SCALE();
        assertBalances(creatorAccount, initialBalance - price + creatorFee, 2);

        // Verify supply
        assertEq(instance.totalSupply(CREATOR_TOKEN_ID), 2);
    }

    function testBuyFirstShareAsNonCreator() public {
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), 1000 * (10 ** 6));

        instance.buyShares(CREATOR_TOKEN_ID, 1);
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
        instance.buyShares(CREATOR_TOKEN_ID, shareAmount);
        vm.stopPrank();

        assertBalances(buyerAccount, initialBuyerBalance - price, shareAmount);

        // Verify total supply
        assertEq(instance.totalSupply(CREATOR_TOKEN_ID), 1 + shareAmount);
    }

    function testCannotBuyZeroShares() public {
        vm.startPrank(creatorAccount);
        vm.expectRevert("Amount must be greater than zero");
        instance.buyShares(CREATOR_TOKEN_ID, 0);
        vm.stopPrank();
    }

    function testBuyMultipleSharesBatch() public {
        // Multiple users buy shares
        uint256 buyerShareAmount = 2;
        uint256 anotherBuyerShareAmount = 5;

        uint256 buyerPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, buyerShareAmount);

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), buyerPrice);
        instance.buyShares(CREATOR_TOKEN_ID, buyerShareAmount);
        vm.stopPrank();

        uint256 anotherBuyerPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, anotherBuyerShareAmount);

        vm.startPrank(anotherBuyerAccount);
        mockUsdc.approve(address(instance), anotherBuyerPrice);
        instance.buyShares(CREATOR_TOKEN_ID, anotherBuyerShareAmount);
        vm.stopPrank();

        // Verify balances
        assertEq(instance.balanceOf(creatorAccount, CREATOR_TOKEN_ID), 1);
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
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount);

        // Buyer sells 1 share
        uint256 sellAmount = 1;
        uint256 balanceBefore = mockUsdc.balanceOf(buyerAccount);
        instance.sellShares(CREATOR_TOKEN_ID, sellAmount);
        uint256 balanceAfter = mockUsdc.balanceOf(buyerAccount);
        vm.stopPrank();

        // Verify share balances after selling
        assertEq(instance.balanceOf(buyerAccount, CREATOR_TOKEN_ID), buyAmount - sellAmount);
        assertEq(instance.totalSupply(CREATOR_TOKEN_ID), 1 + buyAmount - sellAmount);

        // Verify USDC balance increased (received funds from sale)
        assertTrue(balanceAfter > balanceBefore, "Balance should increase after selling");
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
    }

    function testSellMultipleShares() public {
        // Buyer buys shares
        uint256 buyAmount = 5;
        uint256 buyPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, buyAmount);

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), buyPrice);
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount);

        // Buyer sells multiple shares
        uint256 sellAmount = 3;
        uint256 balanceBefore = mockUsdc.balanceOf(buyerAccount);
        instance.sellShares(CREATOR_TOKEN_ID, sellAmount);
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
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount);

        // Attempt to sell more than owned
        vm.expectRevert("Insufficient shares");
        instance.sellShares(CREATOR_TOKEN_ID, buyAmount + 1);
        vm.stopPrank();
    }

    function testCannotSellAllRemainingShares() public {
        vm.startPrank(creatorAccount);
        // Creator attempts to sell all shares
        vm.expectRevert("Cannot sell shares if it makes supply zero or less through this method");
        instance.sellShares(CREATOR_TOKEN_ID, 1);
        vm.stopPrank();
    }

    function testFeeDistribution() public {
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
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount);
        vm.stopPrank();

        // Calculate expected fees
        uint256 expectedDevFee = buyPrice * DEV_FEE_PERCENT / instance.BPS_SCALE();
        uint256 expectedCreatorFee = buyPrice * CREATOR_FEE_PERCENT / instance.BPS_SCALE();
        uint256 expectedTradingPoolFee = buyPrice * TRADING_POOL_FEE_PERCENT / instance.BPS_SCALE();
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

    function testDivisor() public {
        FriendKey.RoomTier tier = FriendKey.RoomTier.Club;
        vm.startPrank(creatorAccount);
        uint256 tokenId = instance.registerCreator(tier, 0);
        vm.stopPrank();
        uint256 divisor = instance.getDivisor(tokenId);
        assertEq(divisor, 40, "Divisor for Club tier should be 40");
    }

    function testRegisterCreatorWithAdditionalParameters() public {
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
            uint256 devFee = (price * DEV_FEE_PERCENT) / BPS_SCALE;
            creatorFee = (price * CREATOR_FEE_PERCENT) / BPS_SCALE;
            uint256 tradingPoolFee = (price * TRADING_POOL_FEE_PERCENT) / BPS_SCALE;
            expectedCost = price + devFee + creatorFee + tradingPoolFee;
        }

        vm.startPrank(newCreator);
        mockUsdc.approve(address(instance), expectedCost);
        uint256 tokenId = instance.registerCreator(tier, additionalKeys);
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
        uint256 anotherTokenId = instance.registerCreator(FriendKey.RoomTier.Exclusive, 0);
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
}
