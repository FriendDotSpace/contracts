// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IFriendKey} from "./interfaces/IFriendKey.sol";
import {IFriendRoomManager} from "./interfaces/IFriendRoomManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDlnSource} from "./interfaces/IDlnSource.sol";
import {DlnOrderLib} from "./libraries/DlnOrderLib.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title FriendPool
 * @author FriendDotSpace
 * @notice A pool contract that manages bonding curve reserves and cross-chain functionality
 * @custom:oz-upgrades-from FriendPool
 * @dev This contract provides the following features:
 *      - Reserve management for bonding curve tokens
 *      - Cross-chain integration via DLN (deBridge Liquidity Network)
 *      - Authorized fund dispatching across chains
 *      - Integration with FriendKey contract for automatic fee collection
 *      - Upgradeable contract using UUPS proxy pattern
 */
contract FriendPoolV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice The FriendKey contract that can pull funds from this pool
    IFriendKey public friendKey;
    /// @dev Private address authorized to dispatch funds cross-chain
    address private _dispatcher;
    /// @notice The DLN Source contract for cross-chain operations
    IDlnSource public dlnSource;

    /// @notice Mapping from token ID to amount of reserves held in the pool
    /// @dev These reserves come from trading pool fees collected by FriendKey
    mapping(uint256 => uint256) public poolReserves;

    /// @notice Flat dispatch fee (in bonding token units) charged per cross-chain dispatch
    uint256 public dispatchFee;

    /// @notice Emitted when funds are pulled from reserves by FriendKey contract
    /// @param tokenId The creator token ID associated with the reserves
    /// @param amount Amount of tokens pulled
    /// @param totalReserves Total reserves remaining for this token ID
    event FundsPulled(uint256 indexed tokenId, uint256 amount, uint256 totalReserves);

    /// @notice Emitted when dispatcher is set
    /// @param dispatcher The address of the dispatcher
    event DispatcherSet(address indexed dispatcher);

    /// @notice Emitted when external funds are deposited (e.g., tips) into a room's pool reserves
    /// @param tokenId The creator token ID associated with the reserves
    /// @param from The address providing the funds
    /// @param amount Amount deposited
    /// @param totalReserves Total reserves after deposit
    event FundsDeposited(uint256 indexed tokenId, address indexed from, uint256 amount, uint256 totalReserves);

    /// @notice Emitted when funds are dispatched cross-chain
    /// @param tokenId The token ID associated with the dispatched funds
    /// @param amount Amount of tokens dispatched
    /// @param netAmount Amount of tokens dispatched after deducting the dispatch fee (amount - dispatchFee)
    /// @param orderId The DLN order ID for tracking the cross-chain transaction
    event FundsDispatched(uint256 indexed tokenId, uint256 amount, uint256 netAmount, bytes32 orderId);

    /// @notice Emitted when the flat dispatch fee is updated
    /// @param newFee The new dispatch fee in bonding token units
    event DispatchFeeSet(uint256 newFee);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the FriendPool contract
     * @dev This function replaces the constructor in upgradeable contracts
     * @param initialOwner The address that will own this contract
     * @param _friendKey Address of the FriendKey contract that will interact with this pool
     * @param _dlnSource Address of the DLN Source contract for cross-chain functionality
     */
    function initialize(address initialOwner, address _friendKey, address _dlnSource) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        if (_friendKey == address(0)) revert Errors.ZeroAddress();
        friendKey = IFriendKey(_friendKey);

        if (_dlnSource == address(0)) revert Errors.ZeroAddress();
        dlnSource = IDlnSource(_dlnSource);
    }

    /**
     * @dev Authorizes contract upgrades - only callable by owner
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Modifier to ensure only the FriendKey contract can call certain functions
     */
    modifier onlyFriendKey() {
        _onlyFriendKey();
        _;
    }

    function _onlyFriendKey() internal view {
        if (msg.sender != address(friendKey)) revert Errors.NotFriendKey();
    }

    /**
     * @dev Modifier to check if contract is paused via FriendKey -> RoomManager
     */
    modifier whenNotPaused() {
        address roomManagerAddress = friendKey.roomManager();
        if (roomManagerAddress != address(0)) {
            if (IFriendRoomManager(roomManagerAddress).paused()) revert Errors.ContractPaused();
        }
        _;
    }

    /**
     * @notice Sets the authorized dispatcher address for cross-chain operations
     * @dev Only callable by contract owner
     * @param dispatcher The address authorized to dispatch funds cross-chain
     */
    function setDispatcher(address dispatcher) external onlyOwner {
        if (dispatcher == address(0)) revert Errors.ZeroAddress();
        _dispatcher = dispatcher;
        emit DispatcherSet(dispatcher);
    }

    /**
     * @notice Sets the flat dispatch fee charged on each cross-chain dispatch
     * @dev Only callable by owner. Fee is denominated in the bonding token's smallest units.
     * @param newFee The new dispatch fee amount
     */
    function setDispatchFee(uint256 newFee) external onlyOwner {
        dispatchFee = newFee;
        emit DispatchFeeSet(newFee);
    }

    /**
     * @notice Dispatches funds cross-chain for a specific token ID
     * @dev Only callable by authorized dispatcher or contract owner
     * @param tokenId The token ID whose reserves to dispatch
     * @param data The DLN order creation data for cross-chain transfer
     * @param _salt Salt for deterministic order ID generation
     * @return The amount of tokens dispatched
     */
    function dispatchAs(uint256 tokenId, DlnOrderLib.OrderCreation calldata data, uint64 _salt)
        external
        payable
        whenNotPaused
        returns (uint256)
    {
        if (msg.sender != _dispatcher && msg.sender != owner()) revert Errors.NotDispatcher();
        uint256 amount = _dispatch(tokenId, data, _salt);
        return amount;
    }

    /**
     * @notice Internal function to execute cross-chain dispatch via DLN
     * @dev Handles the actual token transfer and DLN order creation
     * @param tokenId The token ID whose reserves to dispatch
     * @param _orderCreation The DLN order creation parameters
     * @param _salt Salt for deterministic order ID generation
     * @return The amount of tokens dispatched
     */
    function _dispatch(uint256 tokenId, DlnOrderLib.OrderCreation calldata _orderCreation, uint64 _salt)
        internal
        returns (uint256)
    {
        uint256 amount = poolReserves[tokenId];
        if (amount == 0) revert Errors.NoFundsAvailable();
        if (amount <= dispatchFee) revert Errors.InsufficientReserves();

        // Deduct a flat dispatch fee and bridge the net amount.
        uint256 netAmount = amount - dispatchFee;
        if (_orderCreation.giveAmount != netAmount) revert Errors.InvalidAmount();

        IERC20 bondingToken = IERC20(friendKey.bondingToken());
        if (bondingToken.balanceOf(address(this)) < amount) revert Errors.InsufficientReserves();

        // remove funds from pool reserves
        poolReserves[tokenId] -= amount;

        // pay dispatch fee to dev destination
        address devDest;
        (devDest,) = friendKey.getFeeDestinations();
        if (devDest == address(0)) revert Errors.ZeroAddress();
        bondingToken.safeTransfer(devDest, dispatchFee);

        // approve funds to recipient
        bondingToken.forceApprove(address(dlnSource), netAmount);

        // dispatch funds to recipient
        bytes32 orderId = dlnSource.createSaltedOrder{value: msg.value}(_orderCreation, _salt, "", 0, "", "");

        emit FundsDispatched(tokenId, amount, netAmount, orderId);
        return netAmount;
    }

    /**
     * @notice Deposits bonding tokens into a room's pool reserves (e.g., tips or manual funding)
     * @dev Anyone can call; requires ERC20 allowance. Credits poolReserves so funds are dispatchable.
     * @param tokenId The token ID whose pool reserves to credit
     * @param amount Amount of bonding tokens to transfer in and credit
     */
    function depositToPool(uint256 tokenId, uint256 amount) external whenNotPaused {
        uint256 newReserves = _collectToPool(tokenId, amount, msg.sender);
        emit FundsDeposited(tokenId, msg.sender, amount, newReserves);
    }

    /**
     * @notice Pulls trading pool fees from FriendKey contract into pool reserves
     * @dev Only callable by the FriendKey contract during trading operations
     * @param tokenId The token ID to associate the pulled funds with
     * @param amount Amount of bonding tokens to pull into reserves
     */
    function pull(uint256 tokenId, uint256 amount) external onlyFriendKey whenNotPaused {
        uint256 newReserves = _collectToPool(tokenId, amount, msg.sender);
        emit FundsPulled(tokenId, amount, newReserves);
    }

    /**
     * @dev Internal helper to collect bonding tokens into pool reserves from a given address.
     *
     */
    function _collectToPool(uint256 tokenId, uint256 amount, address from) internal returns (uint256) {
        if (amount == 0) revert Errors.AmountMustBeGreaterThanZero();
        if (friendKey.creatorByTokenId(tokenId) == address(0)) revert Errors.CreatorNotRegistered();

        IERC20 bondingToken = IERC20(friendKey.bondingToken());
        if (bondingToken.allowance(from, address(this)) < amount) revert Errors.InsufficientAllowance();
        if (bondingToken.balanceOf(from) < amount) revert Errors.InsufficientBalance();

        bondingToken.safeTransferFrom(from, address(this), amount);
        poolReserves[tokenId] += amount;

        return poolReserves[tokenId];
    }

    /**
     * @notice Transfers funds from pool reserves to a room destination, deducting a topup fee
     * @dev Callable only by authority or owner. Deducts topupFeeAmount from the pool reserves
     *      and sends it to dev destination, then transfers the remaining net amount to destination.
     * @param tokenId The token ID whose reserves to transfer
     * @param topupFeeAmount The fee amount (in USDC) to deduct and send to dev destination
     * @param destination The address to receive the net amount after fee deduction
     */
    function transferFundsToRoom(uint256 tokenId, uint256 topupFeeAmount, address destination) external whenNotPaused {
        if (msg.sender != _dispatcher && msg.sender != owner()) revert Errors.CallerNotAuthorityOrOwner();

        uint256 amount = poolReserves[tokenId];
        if (amount == 0) revert Errors.NoFundsAvailable();
        if (amount <= topupFeeAmount) revert Errors.InsufficientReserves();
        if (destination == address(0)) revert Errors.ZeroAddress();

        // Deduct a flat topupFeeAmount fee and transfer the net amount.
        uint256 netAmount = amount - topupFeeAmount;

        IERC20 bondingToken = IERC20(friendKey.bondingToken());
        if (bondingToken.balanceOf(address(this)) < amount) revert Errors.InsufficientReserves();

        // remove funds from pool reserves
        poolReserves[tokenId] -= amount;

        // pay topupFeeAmount fee to dev destination
        if (topupFeeAmount > 0) {
            address devDest;
            (devDest,) = friendKey.getFeeDestinations();
            if (devDest == address(0)) revert Errors.ZeroAddress();
            bondingToken.safeTransfer(devDest, topupFeeAmount);
        }

        // transfer the remaining funds to the destination
        bondingToken.safeTransfer(destination, netAmount);
        emit FundsPulled(tokenId, amount, poolReserves[tokenId]);
    }
}
