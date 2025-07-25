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

contract FriendPool is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20Metadata;

    IFriendKey public friendKey;
    address private _dispatcher;
    IDlnSource public dlnSource;

    // from tokenId to amount of reserves
    mapping(uint256 => uint256) public poolReserves;

    event FundsPulled(uint256 indexed tokenId, uint256 amount, uint256 totalReserves);
    event DispatchAllowed(uint256 indexed tokenId, address indexed recipient);
    event FundsDispatched(uint256 indexed tokenId, uint256 amount, bytes32 orderId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _friendKey, address _dlnSource) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        require(_friendKey != address(0), "FriendPool: FriendKey address cannot be zero");
        friendKey = IFriendKey(_friendKey);

        require(_dlnSource != address(0), "FriendPool: DLN Source address cannot be zero");
        dlnSource = IDlnSource(_dlnSource);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier onlyFriendKey() {
        require(msg.sender == address(friendKey), "FriendPool: Caller is not the FriendKey contract");
        _;
    }

    // modifier onlyKeyCreator(uint256 tokenId) {
    //     address creator = friendKey.creatorByTokenId(tokenId);
    //     require(creator != address(0), "FriendPool: Token does not exist or creator is zero address");
    //     require(creator == msg.sender, "FriendPool: Only the creator can perform this action");
    //     _;
    // }

    function setDispatcher(address dispatcher) external onlyOwner {
        require(dispatcher != address(0), "FriendPool: Dispatcher address cannot be zero");
        _dispatcher = dispatcher;
    }

    function dispatchAs(uint256 tokenId, DlnOrderLib.OrderCreation calldata data, uint64 _salt)
        external
        payable
        returns (uint256)
    {
        require(msg.sender == _dispatcher || msg.sender == owner(), "FriendPool: Caller is not the dispatcher");
        uint256 amount = _dispatch(tokenId, data, _salt);
        return amount;
    }

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

    // DEV: up to discussion with the client
    // function dispatch(uint256 tokenId, DlnOrderLib.OrderCreation calldata data, uint32 _salt)
    //     external
    //     onlyKeyCreator(tokenId)
    //     returns (uint256)
    // {
    //     uint256 amount = _dispatch(tokenId, data, _salt);
    //     return amount;
    // }

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
