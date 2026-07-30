// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// Resolves the custodial fee legs (room fund, platform) per room. Owned by
/// the platform Safe. The creator leg deliberately does NOT resolve here —
/// it lives in each splitter, redirectable by the creator alone.
/// Ownable2Step: a mistaken transferOwnership() cannot brick the registry —
/// the incoming owner must call acceptOwnership() before control moves.
contract RoomRecipientRegistry is Ownable2Step {
    struct Recipients {
        address roomFund;
        address platform;
    }

    mapping(uint256 roomId => Recipients) private _recipients;
    address public defaultPlatformRecipient;

    event RecipientsSet(uint256 indexed roomId, address roomFund, address platform);
    event DefaultPlatformRecipientSet(address recipient);

    constructor(address owner_, address defaultPlatformRecipient_) Ownable(owner_) {
        defaultPlatformRecipient = defaultPlatformRecipient_;
    }

    function setRecipients(uint256 roomId, address roomFund, address platform) external onlyOwner {
        _recipients[roomId] = Recipients(roomFund, platform);
        emit RecipientsSet(roomId, roomFund, platform);
    }

    function setDefaultPlatformRecipient(address recipient) external onlyOwner {
        defaultPlatformRecipient = recipient;
        emit DefaultPlatformRecipientSet(recipient);
    }

    function recipientsOf(uint256 roomId) external view returns (address roomFund, address platform) {
        Recipients memory r = _recipients[roomId];
        roomFund = r.roomFund;
        platform = r.platform == address(0) ? defaultPlatformRecipient : r.platform;
    }
}
