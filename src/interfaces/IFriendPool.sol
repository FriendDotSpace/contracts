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
     * @dev returns the dispatch fee
     */
    function dispatchFee() external view returns (uint256);

    /**
     * @notice Transfers funds from pool reserves to a room destination, deducting a topup fee
     * @dev Callable only by authority or owner. Deducts topupFeeAmount from the pool reserves
     *      and sends it to dev destination, then transfers the remaining net amount to destination.
     * @param tokenId The token ID whose reserves to transfer
     * @param topupFeeAmount The fee amount (in USDC) to deduct and send to dev destination
     * @param destination The address to receive the net amount after fee deduction
     */
    function transferFundsToRoom(uint256 tokenId, uint256 topupFeeAmount, address destination) external;
}
