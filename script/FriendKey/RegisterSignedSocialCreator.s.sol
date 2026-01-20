// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
// import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";

contract RegisterSignedSocialCreatorScript is Script {
    address constant PROXY = 0x7a1B04a98DF35fa44e998bD62FFC1690A109057D; // testnet

    bytes32 private constant REGISTER_CREATOR_TYPEHASH = keccak256(
        "RegisterCreator(address account,uint8 roomType,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)"
    );
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256(bytes("FriendKey"));
    bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, PROXY));
    }

    function _getRegisterCreatorSignature(
        address account,
        FriendKey.RoomType roomType,
        FriendKey.RoomTier tier,
        uint256 additionalKeys,
        string memory metadata,
        uint256 ownerPrivateKey
    ) internal view returns (bytes memory) {
        FriendKey instance = FriendKey(PROXY);
        uint256 nonce = instance.registerCreatorNonces(account);
        bytes32 metadataHash = keccak256(bytes(metadata));
        bytes32 structHash = keccak256(
            abi.encode(
                REGISTER_CREATOR_TYPEHASH, account, uint8(roomType), uint8(tier), additionalKeys, nonce, metadataHash
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function run() public {
        // Get owner private key for signing - REQUIRED for signature
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY_AUTHORITY");
        // Get creator private key for the account that will register
        uint256 privateKeyCreator = vm.envUint("PRIVATE_KEY_CREATOR");

        vm.startBroadcast(privateKeyCreator);

        FriendKey instance = FriendKey(PROXY);
        console2.log("Proxy deployed to %s", address(instance));

        address creator = vm.addr(privateKeyCreator);
        address owner = instance.owner();
        console2.log("Creator:", creator);
        console2.log("Owner:", owner);

        FriendKey.RoomTier tier = FriendKey.RoomTier.Club;
        uint256 additionalKeys = 1;

        string memory metadata;
        try vm.envString("CREATOR_METADATA") returns (string memory value) {
            metadata = value;
        } catch {
            metadata = "QmYRGqHybzVC8nBcUrzQqSsx2BNVE7LpHGXrgQUn2qkxbt";
        }

        // Use the helper function to create the signature, same way as the test file
        bytes memory signature = _getRegisterCreatorSignature(
            creator, FriendKey.RoomType.Social, tier, additionalKeys, metadata, ownerPrivateKey
        );

        // Call the full function signature to match the signed parameters
        instance.registerSocialCreator(tier, additionalKeys, metadata, signature);

        vm.stopBroadcast();
    }
}
