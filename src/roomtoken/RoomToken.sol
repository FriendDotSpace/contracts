// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Fixed-supply room token with a one-way launch state machine:
///   initializing -> gated (finalized, pre-open) -> cap window -> free.
/// There is no path backwards and no mint beyond the constructor.
contract RoomToken is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;

    uint256 public immutable roomId;
    address public immutable factory;
    uint64 public immutable tradingOpensAt;
    uint32 public immutable capWindowSecs;
    uint16 public immutable walletCapBps;

    address public pool;
    address public splitter;
    address public devBuyRecipient;
    uint128 public devBuyMaxOut;
    bool public devBuyConsumed;
    bool public initialized;
    bool public finalized;

    error NotFactory();
    error AlreadyInitialized();
    error AlreadyFinalized();
    error NotInitialized();
    error TransferNotAllowedYet();
    error PreOpenTransferForbidden();
    error WalletCapExceeded();
    error DevBuyNotAuthorized();

    event LaunchInitialized(address pool, address splitter, address devBuyRecipient, uint128 devBuyMaxOut);
    event LaunchFinalized();

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 roomId_,
        address factory_,
        uint64 tradingOpensAt_,
        uint32 capWindowSecs_,
        uint16 walletCapBps_
    ) ERC20(name_, symbol_) {
        roomId = roomId_;
        factory = factory_;
        tradingOpensAt = tradingOpensAt_;
        capWindowSecs = capWindowSecs_;
        walletCapBps = walletCapBps_;
        _mint(factory_, TOTAL_SUPPLY);
    }

    function initializeLaunch(address pool_, address splitter_, address devBuyRecipient_, uint128 devBuyMaxOut_)
        external
        onlyFactory
    {
        if (initialized) revert AlreadyInitialized();
        if (finalized) revert AlreadyFinalized();
        initialized = true;
        pool = pool_;
        splitter = splitter_;
        devBuyRecipient = devBuyRecipient_;
        devBuyMaxOut = devBuyMaxOut_;
        emit LaunchInitialized(pool_, splitter_, devBuyRecipient_, devBuyMaxOut_);
    }

    function finalizeLaunch() external onlyFactory {
        if (!initialized) revert NotInitialized();
        if (finalized) revert AlreadyFinalized();
        finalized = true;
        emit LaunchFinalized();
    }

    function _update(address from, address to, uint256 value) internal override {
        // Constructor mint.
        if (from == address(0)) {
            super._update(from, to, value);
            return;
        }

        if (!finalized) {
            // (a) Position seed: NPM pulls factory -> pool.
            if (from == factory && to == pool && pool != address(0)) {
                super._update(from, to, value);
                return;
            }
            // (b) The single authorized dev buy: pool pays out to the pinned
            // recipient, bounded, nonzero, once. Sequential guards for
            // auditability; a zero-value transfer must never consume the slot.
            if (from == pool && pool != address(0)) {
                if (to != devBuyRecipient) revert PreOpenTransferForbidden();
                if (devBuyConsumed) revert PreOpenTransferForbidden();
                if (devBuyMaxOut == 0 || value == 0 || value > devBuyMaxOut) {
                    revert DevBuyNotAuthorized();
                }
                devBuyConsumed = true;
                super._update(from, to, value);
                return;
            }
            revert PreOpenTransferForbidden();
        }

        if (block.timestamp < tradingOpensAt) revert TransferNotAllowedYet();

        if (block.timestamp < uint256(tradingOpensAt) + capWindowSecs) {
            if (to != pool && to != splitter) {
                if (balanceOf(to) + value > (TOTAL_SUPPLY * walletCapBps) / 10_000) {
                    revert WalletCapExceeded();
                }
            }
        }

        super._update(from, to, value);
    }
}
