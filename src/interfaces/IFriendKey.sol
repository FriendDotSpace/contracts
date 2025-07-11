// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.27;
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @dev Minimal Interface of the FriendKey.
 */
interface IFriendKey is IERC1155 {

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function creatorByTokenId(uint256 tokenId) external view returns (address);
}
