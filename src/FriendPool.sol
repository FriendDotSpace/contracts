// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IFriendKey} from "./interfaces/IFriendKey.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDlnSource} from "./interfaces/IDlnSource.sol";
import "./libraries/DlnOrderLib.sol";

/**
 * @title FriendPool
 * @author FriendDotSpace
 * @notice A pool contract that manages bonding curve reserves and cross-chain functionality
 * @dev This contract provides the following features:
 *      - Reserve management for bonding curve tokens
 *      - Cross-chain integration via DLN (deBridge Liquidity Network)
 *      - Authorized fund dispatching across chains
 *      - Integration with FriendKey contract for automatic fee collection
 *      - Upgradeable contract using UUPS proxy pattern
 */
contract FriendPool is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20Metadata;

    /// @notice The FriendKey contract that can pull funds from this pool
    IFriendKey public friendKey;
    /// @dev Internal address authorized to dispatch funds cross-chain
    address private _dispatcher;
    /// @notice The DLN Source contract for cross-chain operations
    IDlnSource public dlnSource;

    /// @notice Mapping from token ID to amount of reserves held in the pool
    /// @dev These reserves come from trading pool fees collected by FriendKey
    mapping(uint256 => uint256) public poolReserves;

    /// @notice Emitted when funds are pulled from reserves by FriendKey contract
    /// @param tokenId The creator token ID associated with the reserves
    /// @param amount Amount of tokens pulled
    /// @param totalReserves Total reserves remaining for this token ID
    event FundsPulled(uint256 indexed tokenId, uint256 amount, uint256 totalReserves);
    
    /// @notice Emitted when dispatch is allowed for a token ID
    /// @param tokenId The token ID for which dispatch is authorized
    /// @param recipient The address authorized to dispatch funds
    event DispatchAllowed(uint256 indexed tokenId, address indexed recipient);
    
    /// @notice Emitted when funds are dispatched cross-chain
    /// @param tokenId The token ID associated with the dispatched funds
    /// @param amount Amount of tokens dispatched
    /// @param orderId The DLN order ID for tracking the cross-chain transaction
    event FundsDispatched(uint256 indexed tokenId, uint256 amount, bytes32 orderId);

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

        require(_friendKey != address(0), "FriendPool: FriendKey address cannot be zero");
        friendKey = IFriendKey(_friendKey);

        require(_dlnSource != address(0), "FriendPool: DLN Source address cannot be zero");
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
        require(msg.sender == address(friendKey), "FriendPool: Caller is not the FriendKey contract");
        _;
    }

    /**
     * @notice Sets the authorized dispatcher address for cross-chain operations
     * @dev Only callable by contract owner
     * @param dispatcher The address authorized to dispatch funds cross-chain
     */
    function setDispatcher(address dispatcher) external onlyOwner {
        require(dispatcher != address(0), "FriendPool: Dispatcher address cannot be zero");
        _dispatcher = dispatcher;
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
        returns (uint256)
    {
        require(msg.sender == _dispatcher || msg.sender == owner(), "FriendPool: Caller is not the dispatcher");
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
        require(amount > 0, "FriendPool: No funds available for dispatch");

        IERC20Metadata bondingToken = IERC20Metadata(friendKey.bondingToken());
        require(bondingToken.balanceOf(address(this)) >= amount, "FriendPool: Insufficient pool reserves");

        // remove funds from pool reserves
        poolReserves[tokenId] -= amount;

        // approve funds to recipient
        bondingToken.approve(address(dlnSource), amount);

        // dispatch funds to recipient
        bytes32 orderId = dlnSource.createSaltedOrder{value: msg.value}(_orderCreation, _salt, "", 0, "", "");

        emit FundsDispatched(tokenId, amount, orderId);
        return amount;
    }

    /**
     * @notice Pulls trading pool fees from FriendKey contract into pool reserves
     * @dev Only callable by the FriendKey contract during trading operations
     * @param tokenId The token ID to associate the pulled funds with
     * @param amount Amount of bonding tokens to pull into reserves
     * @return True if the transfer was successful
     */
    function pull(uint256 tokenId, uint256 amount) external onlyFriendKey returns (bool) {
        IERC20Metadata bondingToken = IERC20Metadata(friendKey.bondingToken());
        require(bondingToken.balanceOf(msg.sender) >= amount, "FriendPool: Insufficient bonding token balance");
        require(
            bondingToken.allowance(msg.sender, address(this)) >= amount,
            "FriendPool: Insufficient allowance for bonding token"
        );
        bool success = bondingToken.transferFrom(msg.sender, address(this), amount);

        require(success, "FriendPool: Transfer failed");
        poolReserves[tokenId] += amount;

        emit FundsPulled(tokenId, amount, poolReserves[tokenId]);

        return success;
    }
}
