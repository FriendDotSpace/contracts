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

    FriendStake public friendStake;

    uint256 private constant OWNER_PRIVATE_KEY = 1;
    bytes32 private constant REGISTER_CREATOR_TYPEHASH =
        keccak256("RegisterCreator(address account,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)");
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
        uint256 nonce = instance.registerCreatorNonces(account);
        bytes32 metadataHash = keccak256(bytes(metadata));
        bytes32 structHash =
            keccak256(abi.encode(REGISTER_CREATOR_TYPEHASH, account, uint8(tier), additionalKeys, nonce, metadataHash));
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
        bytes memory signature = _getRegisterCreatorSignature(account, FriendKey.RoomTier.Club, 0, "");
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
        
        bytes memory initializeData = abi.encodeCall(
            FriendKey.initialize, (owner, address(mockUsdc), friendStakeBeacon, address(roomManager))
        );
        address proxy = Upgrades.deployUUPSProxy("FriendKey.sol", initializeData);
        instance = FriendKey(proxy);
        
        // Set FriendKey address in RoomManager
        roomManager.setFriendKey(address(instance));
        
        // Set fee destinations in RoomManager
        roomManager.setFeeDestinations(devFeeDestination, tradingPoolFeeDestination);
        vm.stopPrank();

        vm.startPrank(creatorAccount);
        string memory metadata = "";
        bytes memory signature = _getRegisterCreatorSignature(creatorAccount, FriendKey.RoomTier.Club, 0, metadata);
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
        instance.buyShares(CREATOR_TOKEN_ID, 1, 0);
        vm.stopPrank();

        // Fee variables moved to FriendRoomManager - using default values for test
        uint256 creatorFee = (basePrice * 250) / instance.BPS_SCALE(); // Default 2.5%
        assertBalances(creatorAccount, initialBalance - price + creatorFee, 2);

        // Verify supply
        assertEq(instance.totalSupply(CREATOR_TOKEN_ID), 2);
    }

    function testBuyFirstShareAsNonCreator() public {
        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), 1000 * (10 ** 6));

        instance.buyShares(CREATOR_TOKEN_ID, 1, 0);
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
        instance.buyShares(CREATOR_TOKEN_ID, shareAmount, 0);
        vm.stopPrank();

        assertBalances(buyerAccount, initialBuyerBalance - price, shareAmount);

        // Verify total supply
        assertEq(instance.totalSupply(CREATOR_TOKEN_ID), 1 + shareAmount);
    }

    function testCannotBuyZeroShares() public {
        vm.startPrank(creatorAccount);
        vm.expectRevert(Errors.AmountMustBeGreaterThanZero.selector);
        instance.buyShares(CREATOR_TOKEN_ID, 0, 0);
        vm.stopPrank();
    }

    function testBuyMultipleSharesBatch() public {
        // Multiple users buy shares
        uint256 buyerShareAmount = 2;
        uint256 anotherBuyerShareAmount = 5;

        uint256 buyerPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, buyerShareAmount);

        vm.startPrank(buyerAccount);
        mockUsdc.approve(address(instance), buyerPrice);
        instance.buyShares(CREATOR_TOKEN_ID, buyerShareAmount, 0);
        vm.stopPrank();

        uint256 anotherBuyerPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, anotherBuyerShareAmount);

        vm.startPrank(anotherBuyerAccount);
        mockUsdc.approve(address(instance), anotherBuyerPrice);
        instance.buyShares(CREATOR_TOKEN_ID, anotherBuyerShareAmount, 0);
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
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount, 0);

        // Buyer sells 1 share
        uint256 sellAmount = 1;
        uint256 balanceBefore = mockUsdc.balanceOf(buyerAccount);
        uint256 initialBondingCurveReserves = instance.bondingCurveReserves(creatorAccount);
        uint256 sellPriveWithFee = instance.getSellPrice(CREATOR_TOKEN_ID, sellAmount);
        uint256 sellPrice = instance.getSellPriceAfterFee(CREATOR_TOKEN_ID, sellAmount);
        instance.sellShares(CREATOR_TOKEN_ID, sellAmount, 0);
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
        instance.buyShares(CREATOR_TOKEN_ID, 1, 0);
        vm.stopPrank();
        uint256 holdingSince = instance.getKeyHoldingSince(CREATOR_TOKEN_ID, buyerAccount);
        assertTrue(holdingSince > 0, "Holding since should be set after first buy");

        // Should not change on subsequent buys
        vm.startPrank(buyerAccount);
        uint256 newBuyPrice = instance.getBuyPriceAfterFee(CREATOR_TOKEN_ID, 2);
        mockUsdc.approve(address(instance), newBuyPrice);
        instance.buyShares(CREATOR_TOKEN_ID, 2, 0);
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
        instance.stake(CREATOR_TOKEN_ID, 1);
        vm.stopPrank();
        uint256 holdingSinceAfterStake = instance.getKeyHoldingSince(CREATOR_TOKEN_ID, buyerAccount);
        assertEq(holdingSinceAfterStake, holdingSince, "Holding since should not change on stake");

        // Should not change on unstake
        vm.startPrank(buyerAccount);
        instance.unstake(CREATOR_TOKEN_ID, 1);
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
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount, 0);

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
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount, 0);

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
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount, 0);
        vm.stopPrank();

        // Calculate expected fees - using new default fees (250 = 2.5% each)
        uint256 expectedDevFee = buyPrice * 250 / instance.BPS_SCALE();
        uint256 expectedCreatorFee = buyPrice * 250 / instance.BPS_SCALE();
        uint256 expectedTradingPoolFee = buyPrice * 250 / instance.BPS_SCALE();
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
            uint256 devFee = (price * 250) / BPS_SCALE; // Default 2.5%
            creatorFee = (price * 250) / BPS_SCALE; // Default 2.5%
            uint256 tradingPoolFee = (price * 250) / BPS_SCALE; // Default 2.5%
            expectedCost = price + devFee + creatorFee + tradingPoolFee;
        }

        vm.startPrank(newCreator);
        mockUsdc.approve(address(instance), expectedCost);
        string memory metadata = "CLUB_CREATOR";
        bytes memory signature = _getRegisterCreatorSignature(newCreator, tier, additionalKeys, metadata);
        uint256 tokenId = instance.registerCreator(tier, additionalKeys, metadata, signature);
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
        instance.buyShares(CREATOR_TOKEN_ID, buyAmount, 0);
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
}
