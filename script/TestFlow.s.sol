// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendUSD} from "src/FriendUSD.sol";
import {FriendStake} from "src/FriendStake.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestFlow
 * @notice test script - full protocol flow
 * @dev This script tests the complete lifecycle:
 *      1. Creator registers a room
 *      2. Buyer mints USDC and buys shares
 *      3. Buyer stakes shares
 *      4. Buyer unstakes shares
 *      5. Buyer sells shares
 *
 * Environment Variables Required:
 *      PRIVATE_KEY - Creator's private key (deployer)
 *      PRIVATE_KEY_BUYER - Buyer's private key
 *      FRIENDKEY_PROXY - FriendKey proxy address
 *      FRIENDUSD_ADDRESS - FriendUSD token address
 */
contract TestFlowScript is Script {
    // Will be set from environment variables
    address friendKeyProxy;
    address friendUSDAddress;

    bytes32 private constant REGISTER_CREATOR_TYPEHASH = keccak256(
        "RegisterCreator(address account,uint8 roomType,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)"
    );
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256(bytes("FriendKey"));
    bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, friendKeyProxy));
    }

    function setUp() public {}

    function run() public {
        // Get environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 creatorPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 buyerPrivateKey = vm.envUint("PRIVATE_KEY_BUYER");

        friendKeyProxy = 0x7a1B04a98DF35fa44e998bD62FFC1690A109057D; // testnet
        friendUSDAddress = 0x99415d18C146Daf43Fe4D6685224D820Ff03F16d; // testnet

        address creator = vm.addr(creatorPrivateKey);
        address buyer = vm.addr(buyerPrivateKey);

        FriendKey friendKey = FriendKey(friendKeyProxy);
        FriendUSD friendUSD = FriendUSD(friendUSDAddress);

        console2.log("=== Friend.space Test Flow ===");
        console2.log("Creator:", creator);
        console2.log("Buyer:", buyer);
        console2.log("FriendKey:", friendKeyProxy);
        console2.log("FriendUSD:", friendUSDAddress);
        console2.log("");

        // ============================================
        // Step 1: Creator registers a room
        // ============================================
        console2.log("=== Step 1: Creator Registers Room ===");
        vm.startBroadcast(creatorPrivateKey);

        string memory metadata;

        try vm.envString("CREATOR_METADATA") returns (string memory value) {
            metadata = value;
        } catch {
            metadata = "QmWqPGhoU7YgZdtHcWUcPShaqZVT72wzV1PKRwgY271Mrh";
        }

        // Get current nonce for creator
        uint256 nonce = friendKey.registerCreatorNonces(creator);
        console2.log("Creator nonce:", nonce);

        // Create EIP-712 signature
        bytes32 structHash = keccak256(
            abi.encode(
                REGISTER_CREATOR_TYPEHASH,
                creator,
                uint8(FriendKey.RoomType.Trading),
                uint8(FriendKey.RoomTier.Club), // RoomTier.Club
                uint256(0), // no additional keys
                nonce,
                keccak256(bytes(metadata))
            )
        );

        bytes32 domainSeparator = _domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest); // as deployer can sign for creator
        bytes memory signature = abi.encodePacked(r, s, v);

        // Register creator and get token ID
        uint256 tokenId = friendKey.registerCreator(metadata, signature);
        console2.log("Room created! Token ID:", tokenId);
        console2.log("Creator balance:", friendKey.balanceOf(creator, tokenId));

        address stakingPool = friendKey.stakingPoolByTokenId(tokenId);
        console2.log("Staking pool:", stakingPool);

        vm.stopBroadcast();
        console2.log("");

        // ============================================
        // Step 2: Buyer mints USDC and approves
        // ============================================
        console2.log("=== Step 2: Buyer Gets USDC ===");
        vm.startBroadcast(buyerPrivateKey);

        uint256 mintAmount = 30 * 10 ** friendUSD.decimals(); // 30 USDC
        friendUSD.mint(buyer, mintAmount);
        console2.log("Buyer minted USDC:", mintAmount / 10 ** friendUSD.decimals());
        console2.log("Buyer USDC balance:", friendUSD.balanceOf(buyer) / 10 ** friendUSD.decimals());

        // Approve FriendKey to spend USDC
        friendUSD.approve(friendKeyProxy, type(uint256).max);
        console2.log("Buyer approved FriendKey to spend USDC");

        vm.stopBroadcast();
        console2.log("");

        // ============================================
        // Step 3: Buyer buys shares
        // ============================================
        console2.log("=== Step 3: Buyer Buys Shares ===");
        vm.startBroadcast(buyerPrivateKey);

        uint256 sharesToBuy = 5;
        uint256 buyPrice = friendKey.getBuyPriceAfterFee(tokenId, sharesToBuy);
        console2.log("Price to buy %s shares: %s USDC", sharesToBuy, buyPrice / 10 ** friendUSD.decimals());

        uint256 buyerBalanceBefore = friendKey.balanceOf(buyer, tokenId);
        uint256 totalSupplyBefore = friendKey.totalSupply(tokenId);

        // Calculate maxSpend with 5% slippage tolerance for test script
        uint256 maxSpend = (buyPrice * 105) / 100; // 5% buffer
        friendKey.buyShares(tokenId, sharesToBuy, maxSpend);

        uint256 buyerBalanceAfter = friendKey.balanceOf(buyer, tokenId);
        uint256 totalSupplyAfter = friendKey.totalSupply(tokenId);

        console2.log("Buyer balance before:", buyerBalanceBefore);
        console2.log("Buyer balance after:", buyerBalanceAfter);
        console2.log("Total supply before:", totalSupplyBefore);
        console2.log("Total supply after:", totalSupplyAfter);
        console2.log("Buyer USDC balance:", friendUSD.balanceOf(buyer) / 10 ** friendUSD.decimals());

        vm.stopBroadcast();
        console2.log("");

        // ============================================
        // Step 4: Buyer stakes shares
        // ============================================
        console2.log("=== Step 4: Buyer Stakes Shares ===");
        vm.startBroadcast(buyerPrivateKey);

        uint256 sharesToStake = 3;
        console2.log("Staking", sharesToStake, "shares...");

        uint256 balanceBeforeStake = friendKey.balanceOf(buyer, tokenId);
        friendKey.stake(tokenId, sharesToStake);
        uint256 balanceAfterStake = friendKey.balanceOf(buyer, tokenId);

        FriendStake staking = FriendStake(stakingPool);
        // uint256 stakedBalance = staking.stakedBalances(buyer);

        console2.log("Buyer balance before stake:", balanceBeforeStake);
        console2.log("Buyer balance after stake:", balanceAfterStake);
        // console2.log("Staked balance:", stakedBalance);
        console2.log("Total staked in pool:", staking.totalStaked());

        vm.stopBroadcast();
        console2.log("");

        // ============================================
        // Step 5: Buyer unstakes shares
        // ============================================
        console2.log("=== Step 5: Buyer Unstakes Shares ===");
        vm.startBroadcast(buyerPrivateKey);

        uint256 sharesToUnstake = 2;
        console2.log("Unstaking", sharesToUnstake, "shares...");

        uint256 balanceBeforeUnstake = friendKey.balanceOf(buyer, tokenId);
        friendKey.unstake(tokenId, sharesToUnstake);
        uint256 balanceAfterUnstake = friendKey.balanceOf(buyer, tokenId);

        // uint256 stakedBalanceAfterUnstake = staking.stakedBalances(buyer);

        console2.log("Buyer balance before unstake:", balanceBeforeUnstake);
        console2.log("Buyer balance after unstake:", balanceAfterUnstake);
        // console2.log("Staked balance after unstake:", stakedBalanceAfterUnstake);
        console2.log("Total staked in pool:", staking.totalStaked());

        vm.stopBroadcast();
        console2.log("");

        // ============================================
        // Step 6: Buyer sells shares
        // ============================================
        console2.log("=== Step 6: Buyer Sells Shares ===");
        vm.startBroadcast(buyerPrivateKey);

        uint256 sharesToSell = 2;
        uint256 sellPrice = friendKey.getSellPriceAfterFee(tokenId, sharesToSell);
        console2.log("Price to sell %s shares: %s USDC", sharesToSell, sellPrice / 10 ** friendUSD.decimals());

        uint256 usdcBalanceBeforeSell = friendUSD.balanceOf(buyer);
        uint256 buyerSharesBeforeSell = friendKey.balanceOf(buyer, tokenId);
        uint256 totalSupplyBeforeSell = friendKey.totalSupply(tokenId);

        // Calculate minReceive with 5% slippage tolerance for test script
        uint256 minReceive = (sellPrice * 95) / 100; // Accept 5% less than expected
        friendKey.sellShares(tokenId, sharesToSell, minReceive);

        uint256 usdcBalanceAfterSell = friendUSD.balanceOf(buyer);
        uint256 buyerSharesAfterSell = friendKey.balanceOf(buyer, tokenId);
        uint256 totalSupplyAfterSell = friendKey.totalSupply(tokenId);

        console2.log("Buyer shares before:", buyerSharesBeforeSell);
        console2.log("Buyer shares after:", buyerSharesAfterSell);
        console2.log("USDC balance before:", usdcBalanceBeforeSell / 10 ** friendUSD.decimals());
        console2.log("USDC balance after:", usdcBalanceAfterSell / 10 ** friendUSD.decimals());
        console2.log("USDC received:", (usdcBalanceAfterSell - usdcBalanceBeforeSell) / 10 ** friendUSD.decimals());
        console2.log("Total supply before:", totalSupplyBeforeSell);
        console2.log("Total supply after:", totalSupplyAfterSell);

        vm.stopBroadcast();
        console2.log("");

        // ============================================
        // Final Summary
        // ============================================
        console2.log("=== Test Flow Complete! ===");
        console2.log("Token ID:", tokenId);
        console2.log("Creator final balance:", friendKey.balanceOf(creator, tokenId));
        console2.log("Buyer final balance:", friendKey.balanceOf(buyer, tokenId));
        // console2.log("Buyer staked balance:", staking.stakedBalances(buyer));
        console2.log("Total supply:", friendKey.totalSupply(tokenId));
        console2.log("Total staked:", staking.totalStaked());
        console2.log("Buyer final USDC:", friendUSD.balanceOf(buyer) / 10 ** friendUSD.decimals());
        console2.log("");
        console2.log("All operations completed successfully!");
    }
}
