// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title Errors
 * @notice Shared custom errors for gas optimization across contracts
 */
library Errors {
    // Common errors
    error ZeroAddress();
    error AmountMustBeGreaterThanZero();
    error InsufficientBalance();
    error InsufficientAllowance();
    error TransferFailed();
    error ApproveFailed();

    // FriendKey specific errors
    error TotalFeePercentTooHigh();
    error InvalidDuration();
    error InvalidDecimals();
    error InvalidDivisor();
    error CreatorNotRegistered();
    error AmountExceedsSupply();
    error OnlyCreatorCanBuyFirstShare();
    error SlippageExceededMaxSpend();
    error InvalidTier();
    error CreatorAlreadyRegistered();
    error SlippageExceededMinReceive();
    error InsufficientShares();
    error CannotSellAllShares();
    error StakingPoolNotRegistered();
    error StakingPoolNotOpen();
    error UserDoesNotHoldToken();
    error UnauthorizedRegisterSignature();
    error TierNotAllowedForRoomType();
    // FriendPool specific errors
    error NotFriendKey();
    error NotDispatcher();
    error NoFundsAvailable();
    error InsufficientReserves();


    // FriendRoomManager specific errors
    error RoomManagerNotSet();
    error RoomLimitExceeded();
    error RoomTypeNotEnabled();
    error RoomTierNotEnabled();
}

