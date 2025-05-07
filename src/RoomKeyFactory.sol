// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {RoomKey} from "./RoomKey.sol";

contract RoomKeyFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public roomKeyImplementation;

    event RoomCreated(
        address indexed roomKeyAddress,
        address indexed roomContractOwner,
        string name,
        string symbol,
        address creatorFeeRecipient
    );

    event ImplementationUpdated(address indexed newImplementation);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _roomKeyImplementation) public initializer {
        __Ownable_init(initialOwner);
        require(_roomKeyImplementation != address(0), "Factory: Implementation is zero address");
        roomKeyImplementation = _roomKeyImplementation;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setRoomKeyImplementation(address _newImplementation) public onlyOwner {
        require(_newImplementation != address(0), "Factory: New implementation is zero address");
        roomKeyImplementation = _newImplementation;
        emit ImplementationUpdated(_newImplementation);
    }

    function createRoom(
        string memory name,
        string memory symbol,
        address roomContractOwner, // Owner of the RoomKey contract instance (can upgrade it)
        address creatorFeeRecipient, // Recipient of creator's fees
        address devFeeRecipient,
        address tradingPoolFeeRecipient
    ) public returns (address) {
        require(roomContractOwner != address(0), "Factory: Room contract owner is zero address");
        require(creatorFeeRecipient != address(0), "Factory: Creator fee recipient is zero address");
        require(devFeeRecipient != address(0), "Factory: Dev fee recipient is zero address");
        require(tradingPoolFeeRecipient != address(0), "Factory: Trading pool fee recipient is zero address");

        address roomKeyProxy = Clones.clone(roomKeyImplementation);
        RoomKey(payable(roomKeyProxy)).initialize(
            name, symbol, roomContractOwner, creatorFeeRecipient, devFeeRecipient, tradingPoolFeeRecipient
        );

        emit RoomCreated(roomKeyProxy, roomContractOwner, name, symbol, creatorFeeRecipient);
        return roomKeyProxy;
    }
}
