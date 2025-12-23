// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.27;

/**
 * @dev Minimal Interface of the FriendPool.
 */
interface IFriendPool {
    /**
     * @dev pulls the funds from the FriendKey contract.
     */
    function pull(uint256 tokenId, uint256 amount) external;

    /**
     * @dev gets the dispatch fee.
     */
    function dispatchFee() external view returns (uint256);
}
