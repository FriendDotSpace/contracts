// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MockBridge} from "../src/mocks/MockBridge.sol";
import {DlnOrderLib} from "../src/libraries/DlnOrderLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract MockBridgeTest is Test {
    MockBridge public bridge;
    MockToken public token;
    address public owner;
    address public user;

    function setUp() public {
        owner = address(0x1);
        user = address(0x2);

        vm.startPrank(owner);
        bridge = new MockBridge(owner);
        vm.stopPrank();

        token = new MockToken();

        // Transfer some tokens to user for testing
        token.transfer(user, 10000 * 10 ** 18);
    }

    function testGlobalFixedNativeFee() public view {
        uint88 fee = bridge.globalFixedNativeFee();
        assertEq(fee, 0.001 ether);
    }

    function testGlobalTransferFeeBps() public view {
        uint16 feeBps = bridge.globalTransferFeeBps();
        assertEq(feeBps, 10);
    }

    function testCreateOrderWithERC20() public {
        uint256 giveAmount = 1000 * 10 ** 18;

        // Create order creation struct
        DlnOrderLib.OrderCreation memory orderCreation = DlnOrderLib.OrderCreation({
            giveTokenAddress: address(token),
            giveAmount: giveAmount,
            takeTokenAddress: abi.encodePacked(address(0x3)),
            takeAmount: 2000 * 10 ** 18,
            takeChainId: 1,
            receiverDst: abi.encodePacked(address(0x4)),
            givePatchAuthoritySrc: address(0),
            orderAuthorityAddressDst: abi.encodePacked(address(0x5)),
            allowedTakerDst: "",
            externalCall: "",
            allowedCancelBeneficiarySrc: ""
        });

        vm.startPrank(user);

        // Approve the bridge to spend tokens
        token.approve(address(bridge), giveAmount);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 userBalanceBefore = token.balanceOf(user);

        // Create order
        bytes32 orderId = bridge.createOrder(orderCreation, "", 0, "");

        vm.stopPrank();

        // Check that tokens were transferred to owner
        assertEq(token.balanceOf(owner), ownerBalanceBefore + giveAmount);
        assertEq(token.balanceOf(user), userBalanceBefore - giveAmount);
        assertGt(uint256(orderId), 0);
    }

    function testCreateOrderWithNativeToken() public {
        uint256 giveAmount = 1 ether;

        // Create order creation struct for native token
        DlnOrderLib.OrderCreation memory orderCreation = DlnOrderLib.OrderCreation({
            giveTokenAddress: address(0), // Native token
            giveAmount: giveAmount,
            takeTokenAddress: abi.encodePacked(address(0x3)),
            takeAmount: 2000 * 10 ** 18,
            takeChainId: 1,
            receiverDst: abi.encodePacked(address(0x4)),
            givePatchAuthoritySrc: address(0),
            orderAuthorityAddressDst: abi.encodePacked(address(0x5)),
            allowedTakerDst: "",
            externalCall: "",
            allowedCancelBeneficiarySrc: ""
        });

        vm.deal(user, 10 ether);
        vm.startPrank(user);

        uint256 ownerBalanceBefore = owner.balance;
        uint256 userBalanceBefore = user.balance;

        // Create order with native token
        bytes32 orderId = bridge.createOrder{value: giveAmount}(orderCreation, "", 0, "");

        vm.stopPrank();

        // Check that native tokens were transferred to owner
        assertEq(owner.balance, ownerBalanceBefore + giveAmount);
        assertEq(user.balance, userBalanceBefore - giveAmount);
        assertGt(uint256(orderId), 0);
    }

    function testCreateSaltedOrder() public {
        uint256 giveAmount = 500 * 10 ** 18;
        uint64 salt = 12345;

        // Create order creation struct
        DlnOrderLib.OrderCreation memory orderCreation = DlnOrderLib.OrderCreation({
            giveTokenAddress: address(token),
            giveAmount: giveAmount,
            takeTokenAddress: abi.encodePacked(address(0x3)),
            takeAmount: 1000 * 10 ** 18,
            takeChainId: 1,
            receiverDst: abi.encodePacked(address(0x4)),
            givePatchAuthoritySrc: address(0),
            orderAuthorityAddressDst: abi.encodePacked(address(0x5)),
            allowedTakerDst: "",
            externalCall: "",
            allowedCancelBeneficiarySrc: ""
        });

        vm.startPrank(user);

        // Approve the bridge to spend tokens
        token.approve(address(bridge), giveAmount);

        uint256 ownerBalanceBefore = token.balanceOf(owner);

        // Create salted order
        bytes32 orderId = bridge.createSaltedOrder(orderCreation, salt, "", 0, "", "");

        vm.stopPrank();

        // Check that tokens were transferred to owner
        assertEq(token.balanceOf(owner), ownerBalanceBefore + giveAmount);
        assertGt(uint256(orderId), 0);

        // Verify deterministic order ID
        bytes32 expectedOrderId = keccak256(abi.encodePacked(user, salt, address(token), giveAmount));
        assertEq(orderId, expectedOrderId);
    }

    function testSetFees() public {
        uint88 newNativeFee = 0.002 ether;
        uint16 newFeeBps = 20;

        vm.startPrank(owner);

        bridge.setGlobalFixedNativeFee(newNativeFee);
        bridge.setGlobalTransferFeeBps(newFeeBps);

        vm.stopPrank();

        assertEq(bridge.globalFixedNativeFee(), newNativeFee);
        assertEq(bridge.globalTransferFeeBps(), newFeeBps);
    }

    function testOnlyOwnerCanSetFees() public {
        vm.startPrank(user);

        vm.expectRevert();
        bridge.setGlobalFixedNativeFee(0.002 ether);

        vm.expectRevert();
        bridge.setGlobalTransferFeeBps(20);

        vm.stopPrank();
    }

    function testEmergencyRecover() public {
        uint256 amount = 100 * 10 ** 18;

        // Transfer some tokens to the bridge contract
        bool success = token.transfer(address(bridge), amount);
        assertTrue(success);

        vm.startPrank(owner);

        uint256 ownerBalanceBefore = token.balanceOf(owner);

        // Recover tokens
        bridge.emergencyRecover(address(token), amount);

        vm.stopPrank();

        assertEq(token.balanceOf(owner), ownerBalanceBefore + amount);
        assertEq(token.balanceOf(address(bridge)), 0);
    }

    function testRevertZeroGiveAmount() public {
        DlnOrderLib.OrderCreation memory orderCreation = DlnOrderLib.OrderCreation({
            giveTokenAddress: address(token),
            giveAmount: 0, // Zero amount should revert
            takeTokenAddress: abi.encodePacked(address(0x3)),
            takeAmount: 1000 * 10 ** 18,
            takeChainId: 1,
            receiverDst: abi.encodePacked(address(0x4)),
            givePatchAuthoritySrc: address(0),
            orderAuthorityAddressDst: abi.encodePacked(address(0x5)),
            allowedTakerDst: "",
            externalCall: "",
            allowedCancelBeneficiarySrc: ""
        });

        vm.startPrank(user);

        vm.expectRevert("MockBridge: give amount must be greater than 0");
        bridge.createOrder(orderCreation, "", 0, "");

        vm.stopPrank();
    }
}
