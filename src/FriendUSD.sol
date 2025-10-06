// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title FriendUSD
 * @author FriendDotSpace
 * @notice A stablecoin contract with minting and burning capabilities.
 * @dev This contract allows the owner to mint tokens and anyone to burn their tokens.
 *      The owner can mint up to 100 tokens at a time for non-owner addresses.
 *      CONTRACT SHOULD BE USED ONLY FOR TESTNET AND ONBOARDING PURPOSES.
 */
contract FriendUSD is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    constructor(address initialOwner) ERC20("FriendUSD", "FUSD") Ownable(initialOwner) ERC20Permit("FriendUSD") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) public {
        require(amount > 0, "FriendUSD: Mint amount must be greater than zero");

        if (msg.sender != owner()) {
            require(amount <= 100 * 10 ** decimals(), "FriendUSD: Cannot mint more than 100 tokens at once");
        }

        _mint(to, amount);
    }
}
