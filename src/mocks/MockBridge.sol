// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDlnSource} from "../interfaces/IDlnSource.sol";
import {DlnOrderLib} from "../libraries/DlnOrderLib.sol";

contract MockBridge is Ownable, IDlnSource {
    using SafeERC20 for IERC20;

    // Events
    event OrderCreated(bytes32 indexed orderId, address indexed token, uint256 amount);
    event TokensTransferredToOwner(address indexed token, uint256 amount);

    // State variables for fees
    uint88 private _globalFixedNativeFee = 0.001 ether; // 0.001 ETH
    uint16 private _globalTransferFeeBps = 10; // 0.1% (10 basis points)

    // Counter for generating order IDs
    uint256 private _orderNonce;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice Returns the global fixed fee in the native asset of the protocol
     * @return uint88 The global fixed fee in the native asset
     */
    function globalFixedNativeFee() external view override returns (uint88) {
        return _globalFixedNativeFee;
    }

    /**
     * @notice Returns the global transfer fee in basis points
     * @return uint16 The global transfer fee in BPS
     */
    function globalTransferFeeBps() external view override returns (uint16) {
        return _globalTransferFeeBps;
    }

    /**
     * @notice Creates a new order with pseudo-random orderId
     * @dev Transfers the give token to the contract owner
     * @param _orderCreation Order creation parameters
     * @return bytes32 The order ID
     */
    function createOrder(
        DlnOrderLib.OrderCreation calldata _orderCreation,
        bytes calldata /* _affiliateFee */,
        uint32 /* _referralCode */,
        bytes calldata /* _permitEnvelope */
    ) external payable override returns (bytes32) {
        // Generate pseudo-random order ID
        bytes32 orderId = keccak256(
            abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                msg.sender,
                _orderNonce++
            )
        );

        _processOrder(_orderCreation, orderId);
        
        return orderId;
    }

    /**
     * @notice Creates a new order with deterministic orderId
     * @dev Transfers the give token to the contract owner
     * @param _orderCreation Order creation parameters
     * @param _salt Salt for deterministic order ID generation
     * @return bytes32 The order ID
     */
    function createSaltedOrder(
        DlnOrderLib.OrderCreation calldata _orderCreation,
        uint64 _salt,
        bytes calldata /* _affiliateFee */,
        uint32 /* _referralCode */,
        bytes calldata /* _permitEnvelope */,
        bytes calldata /* _metadata */
    ) external payable override returns (bytes32) {
        // Generate deterministic order ID using salt
        bytes32 orderId = keccak256(
            abi.encodePacked(
                msg.sender,
                _salt,
                _orderCreation.giveTokenAddress,
                _orderCreation.giveAmount
            )
        );

        _processOrder(_orderCreation, orderId);
        
        return orderId;
    }

    /**
     * @notice Internal function to process the order and transfer tokens
     * @param _orderCreation Order creation parameters
     * @param orderId The generated order ID
     */
    function _processOrder(
        DlnOrderLib.OrderCreation calldata _orderCreation,
        bytes32 orderId
    ) internal {
        require(_orderCreation.giveAmount > 0, "MockBridge: give amount must be greater than 0");
        
        address giveToken = _orderCreation.giveTokenAddress;
        uint256 giveAmount = _orderCreation.giveAmount;
        
        // Handle native token (ETH) transfer
        if (giveToken == address(0)) {
            require(msg.value >= giveAmount, "MockBridge: insufficient native token sent");
            
            // Transfer native tokens to owner
            (bool success, ) = payable(owner()).call{value: giveAmount}("");
            require(success, "MockBridge: native token transfer failed");
            
            // Refund excess native tokens to sender
            if (msg.value > giveAmount) {
                (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - giveAmount}("");
                require(refundSuccess, "MockBridge: refund failed");
            }
        } else {
            // Handle ERC20 token transfer
            IERC20 token = IERC20(giveToken);
            
            // Transfer tokens from sender to this contract first
            token.safeTransferFrom(msg.sender, owner(), giveAmount);
            
            // Then transfer to owner
            // token.safeTransfer(owner(), giveAmount);
        }
        
        emit OrderCreated(orderId, giveToken, giveAmount);
        emit TokensTransferredToOwner(giveToken, giveAmount);
    }

    /**
     * @notice Allows owner to update the global fixed native fee
     * @param newFee The new fee amount
     */
    function setGlobalFixedNativeFee(uint88 newFee) external onlyOwner {
        _globalFixedNativeFee = newFee;
    }

    /**
     * @notice Allows owner to update the global transfer fee in basis points
     * @param newFeeBps The new fee in basis points
     */
    function setGlobalTransferFeeBps(uint16 newFeeBps) external onlyOwner {
        require(newFeeBps <= 10000, "MockBridge: fee cannot exceed 100%");
        _globalTransferFeeBps = newFeeBps;
    }

    /**
     * @notice Emergency function to recover stuck tokens
     * @param token The token address (address(0) for native tokens)
     * @param amount The amount to recover
     */
    function emergencyRecover(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "MockBridge: recovery failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }
}