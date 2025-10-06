// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FriendFaucet
 * @author FriendDotSpace
 * @notice A faucet contract to distribute bonding curve tokens for testing and onboarding purposes.
 * @dev This contract allows users to mint a limited amount of bonding curve tokens for free.
 *      The owner can withdraw tokens and change the bonding token address.
 *      CONTRACT SHOULD BE USED ONLY FOR TESTNET AND ONBOARDING PURPOSES.
 */
contract FriendFaucet is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public bondingToken;

    event Distributed(address indexed to, uint256 amount, uint256 value);

    constructor(address initialOwner, address _bondingToken) Ownable(initialOwner) {
        require(_bondingToken != address(0), "FriendFaucet: Invalid token address");
        bondingToken = IERC20(_bondingToken);
    }

    function mint(address to, uint256 amount) public payable {
        require(amount > 0, "FriendFaucet: Mint amount must be greater than zero");

        if (msg.sender != owner()) {
            require(amount <= 100 * 10 ** 6, "FriendFaucet: Cannot mint more than 100 tokens at once");
        }

        // check if the contract has enough tokens to distribute
        uint256 contractBalance = bondingToken.balanceOf(address(this));
        require(contractBalance >= amount, "FriendFaucet: Not enough tokens in the faucet");

        bondingToken.safeTransfer(to, amount);

        if (msg.value > 0) {
            payable(to).transfer(msg.value);
        }

        emit Distributed(to, amount, msg.value);
    }

    // function to withdraw tokens from the faucet
    function withdrawAllTokens(address to) public onlyOwner {
        uint256 contractBalance = bondingToken.balanceOf(address(this));
        require(contractBalance > 0, "FriendFaucet: No tokens to withdraw");

        bondingToken.safeTransfer(to, contractBalance);
        emit Distributed(to, contractBalance, 0);
    }

    // function to change the bonding token
    function setBondingToken(address _bondingToken) public onlyOwner {
        require(_bondingToken != address(0), "FriendFaucet: Invalid token address");
        bondingToken = IERC20(_bondingToken);
    }
}
