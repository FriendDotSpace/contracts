// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {FriendUSD} from "src/FriendUSD.sol";

contract FriendUSDTest is Test {
    FriendUSD public friendUSD;

    address public owner;
    address public user1;
    address public user2;

    // Constants for testing
    uint256 public constant DECIMALS = 6;
    uint256 public constant MAX_NON_OWNER_MINT = 100 * 10 ** DECIMALS; // 100 tokens

    function setUp() public {
        owner = vm.addr(1);
        user1 = vm.addr(2);
        user2 = vm.addr(3);

        // Deploy FriendUSD with owner
        friendUSD = new FriendUSD(owner);
    }

    // Test basic mint functionality by owner
    function testMintByOwner() public {
        uint256 mintAmount = 1000 * 10 ** DECIMALS;

        vm.startPrank(owner);
        friendUSD.mint(user1, mintAmount);
        vm.stopPrank();

        assertEq(friendUSD.balanceOf(user1), mintAmount, "Balance should match minted amount");
        assertEq(friendUSD.totalSupply(), mintAmount, "Total supply should match minted amount");
    }

    // Test mint by non-owner within limit
    function testMintByNonOwnerWithinLimit() public {
        uint256 mintAmount = 50 * 10 ** DECIMALS; // 50 tokens, within limit

        vm.startPrank(user1);
        friendUSD.mint(user2, mintAmount);
        vm.stopPrank();

        assertEq(friendUSD.balanceOf(user2), mintAmount, "Balance should match minted amount");
        assertEq(friendUSD.totalSupply(), mintAmount, "Total supply should match minted amount");
    }

    // Test mint by non-owner at exact limit
    function testMintByNonOwnerAtExactLimit() public {
        uint256 mintAmount = MAX_NON_OWNER_MINT; // Exactly 100 tokens

        vm.startPrank(user1);
        friendUSD.mint(user2, mintAmount);
        vm.stopPrank();

        assertEq(friendUSD.balanceOf(user2), mintAmount, "Balance should match minted amount");
        assertEq(friendUSD.totalSupply(), mintAmount, "Total supply should match minted amount");
    }

    // Test mint by non-owner exceeding limit
    function testMintByNonOwnerExceedsLimit() public {
        uint256 mintAmount = MAX_NON_OWNER_MINT + 1; // 100.000001 tokens

        vm.startPrank(user1);
        vm.expectRevert("FriendUSD: Cannot mint more than 100 tokens at once");
        friendUSD.mint(user2, mintAmount);
        vm.stopPrank();
    }

    // Test mint by non-owner with large amount
    function testMintByNonOwnerLargeAmount() public {
        uint256 mintAmount = 1000 * 10 ** DECIMALS; // 1000 tokens

        vm.startPrank(user1);
        vm.expectRevert("FriendUSD: Cannot mint more than 100 tokens at once");
        friendUSD.mint(user2, mintAmount);
        vm.stopPrank();
    }

    // Test owner can mint unlimited amounts
    function testOwnerCanMintUnlimitedAmounts() public {
        uint256 mintAmount = 10000 * 10 ** DECIMALS; // 10,000 tokens

        vm.startPrank(owner);
        friendUSD.mint(user1, mintAmount);
        vm.stopPrank();

        assertEq(friendUSD.balanceOf(user1), mintAmount, "Balance should match large minted amount");
        assertEq(friendUSD.totalSupply(), mintAmount, "Total supply should match large minted amount");
    }

    // Test mint to zero address
    function testMintToZeroAddress() public {
        uint256 mintAmount = 100 * 10 ** DECIMALS;

        vm.startPrank(owner);
        // This should revert due to ERC20's internal _mint function checking for zero address
        vm.expectRevert();
        friendUSD.mint(address(0), mintAmount);
        vm.stopPrank();
    }

    // Test mint zero amount should revert
    function testMintZeroAmount() public {
        vm.startPrank(owner);
        vm.expectRevert("FriendUSD: Mint amount must be greater than zero");
        friendUSD.mint(user1, 0);
        vm.stopPrank();

        // Verify no tokens were minted
        assertEq(friendUSD.balanceOf(user1), 0, "Balance should remain zero");
        assertEq(friendUSD.totalSupply(), 0, "Total supply should remain zero");
    }

    // Test multiple mints by non-owner within limit
    function testMultipleMintsByNonOwnerWithinLimit() public {
        uint256 mintAmount = 50 * 10 ** DECIMALS; // 50 tokens each

        vm.startPrank(user1);
        friendUSD.mint(user2, mintAmount);
        friendUSD.mint(user2, mintAmount);
        vm.stopPrank();

        assertEq(friendUSD.balanceOf(user2), mintAmount * 2, "Balance should be sum of both mints");
        assertEq(friendUSD.totalSupply(), mintAmount * 2, "Total supply should be sum of both mints");
    }

    // Test mint by non-owner to self
    function testMintByNonOwnerToSelf() public {
        uint256 mintAmount = 75 * 10 ** DECIMALS; // 75 tokens

        vm.startPrank(user1);
        friendUSD.mint(user1, mintAmount);
        vm.stopPrank();

        assertEq(friendUSD.balanceOf(user1), mintAmount, "User should receive minted tokens");
        assertEq(friendUSD.totalSupply(), mintAmount, "Total supply should match minted amount");
    }

    // Test mint by owner to multiple recipients
    function testMintByOwnerToMultipleRecipients() public {
        uint256 mintAmount1 = 500 * 10 ** DECIMALS;
        uint256 mintAmount2 = 300 * 10 ** DECIMALS;

        vm.startPrank(owner);
        friendUSD.mint(user1, mintAmount1);
        friendUSD.mint(user2, mintAmount2);
        vm.stopPrank();

        assertEq(friendUSD.balanceOf(user1), mintAmount1, "User1 balance should match first mint");
        assertEq(friendUSD.balanceOf(user2), mintAmount2, "User2 balance should match second mint");
        assertEq(friendUSD.totalSupply(), mintAmount1 + mintAmount2, "Total supply should be sum of all mints");
    }

    // Test edge case: mint exactly one unit above limit
    function testMintOneUnitAboveLimit() public {
        uint256 mintAmount = MAX_NON_OWNER_MINT + 1;

        vm.startPrank(user1);
        vm.expectRevert("FriendUSD: Cannot mint more than 100 tokens at once");
        friendUSD.mint(user2, mintAmount);
        vm.stopPrank();

        // Verify no tokens were minted
        assertEq(friendUSD.balanceOf(user2), 0, "No tokens should be minted on revert");
        assertEq(friendUSD.totalSupply(), 0, "Total supply should remain zero on revert");
    }

    // Test that decimals() returns correct value
    function testDecimals() public view {
        assertEq(friendUSD.decimals(), DECIMALS, "Decimals should be 6");
    }

    // Test token name and symbol
    function testTokenMetadata() public view {
        assertEq(friendUSD.name(), "FriendUSD", "Token name should be FriendUSD");
        assertEq(friendUSD.symbol(), "FUSD", "Token symbol should be FUSD");
    }

    // Test ownership verification
    function testOwnership() public view {
        assertEq(friendUSD.owner(), owner, "Owner should be set correctly");
    }

    // Fuzz test: non-owner mint within valid range
    function testFuzzMintByNonOwnerWithinRange(uint256 amount) public {
        // Bound the amount to valid range (1 to MAX_NON_OWNER_MINT)
        amount = bound(amount, 1, MAX_NON_OWNER_MINT);

        vm.startPrank(user1);
        friendUSD.mint(user2, amount);
        vm.stopPrank();

        assertEq(friendUSD.balanceOf(user2), amount, "Balance should match fuzzed amount");
        assertEq(friendUSD.totalSupply(), amount, "Total supply should match fuzzed amount");
    }

    // Fuzz test: non-owner mint above limit should always revert
    function testFuzzMintByNonOwnerAboveLimit(uint256 amount) public {
        // Bound the amount to be above the limit
        amount = bound(amount, MAX_NON_OWNER_MINT + 1, type(uint256).max);

        vm.startPrank(user1);
        vm.expectRevert("FriendUSD: Cannot mint more than 100 tokens at once");
        friendUSD.mint(user2, amount);
        vm.stopPrank();
    }

    // Fuzz test: owner can mint any amount
    function testFuzzMintByOwner(uint256 amount) public {
        // Bound to reasonable range to avoid overflow issues and ensure amount > 0
        amount = bound(amount, 1, type(uint256).max / 2);

        vm.startPrank(owner);
        friendUSD.mint(user1, amount);
        vm.stopPrank();

        assertEq(friendUSD.balanceOf(user1), amount, "Balance should match fuzzed amount");
        assertEq(friendUSD.totalSupply(), amount, "Total supply should match fuzzed amount");
    }
}
