// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

// contract for mainnet testing of bridge functionality
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDlnSource} from "../interfaces/IDlnSource.sol";
import "../libraries/DlnOrderLib.sol";

contract MockPool is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata public bondingToken;
    address private _dispatcher;
    IDlnSource public dlnSource;

    event FundsDispatched(uint256 indexed tokenId, uint256 amount, bytes32 orderId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _bondingTokenAddress, address _dlnSource) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        require(_bondingTokenAddress != address(0), "FriendPool: FriendKey address cannot be zero");
        bondingToken = IERC20Metadata(_bondingTokenAddress);
        require(_dlnSource != address(0), "FriendPool: DLN Source address cannot be zero");
        dlnSource = IDlnSource(_dlnSource);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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

    function withdraw() external onlyOwner {
        uint256 amount = bondingToken.balanceOf(address(this));
        require(amount > 0, "FriendPool: No funds to withdraw");

        // transfer all funds to owner
        bondingToken.safeTransfer(owner(), amount);
    }

    function _dispatch(uint256 tokenId, DlnOrderLib.OrderCreation calldata _orderCreation, uint64 _salt)
        internal
        returns (uint256)
    {
        uint256 amount = bondingToken.balanceOf(address(this));
        require(amount > 0, "FriendPool: No funds available for dispatch");

        // approve funds to recipient
        bondingToken.approve(address(dlnSource), amount);

        // dispatch funds to recipient

        bytes32 orderId = dlnSource.createSaltedOrder{value: msg.value}(_orderCreation, _salt, "", 0, "", "");

        emit FundsDispatched(tokenId, amount, orderId);
        return amount;
    }
}
