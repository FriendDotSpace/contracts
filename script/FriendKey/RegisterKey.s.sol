// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
// import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";

contract RegisterKeyScript is Script {
    address constant PROXY = 0xe9A3ab633BA3C7071EcBE5975b9322DC1A50a347;

    bytes32 private constant REGISTER_CREATOR_TYPEHASH = keccak256(
        "RegisterCreator(address account,uint8 roomType,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)"
    );
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256(bytes("FriendKey"));
    bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(PROXY);
        console2.log("Proxy deployed to %s", address(instance));

        address creator = vm.addr(deployerPrivateKey);
        uint256 nonce = instance.registerCreatorNonces(creator);
        FriendKey.RoomTier tier = FriendKey.RoomTier.Club;
        uint256 additionalKeys = 0;

        string memory metadata;
        try vm.envString("CREATOR_METADATA") returns (string memory value) {
            metadata = value;
        } catch {
            metadata = "QmWqPGhoU7YgZdtHcWUcPShaqZVT72wzV1PKRwgY271Mrh";
        }
        bytes32 metadataHash = keccak256(bytes(metadata));

        bytes32 domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(instance)));
        bytes32 structHash =
            keccak256(abi.encode(REGISTER_CREATOR_TYPEHASH, creator, uint8(tier), additionalKeys, nonce, metadataHash));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        instance.registerCreator(metadata, signature);

        vm.stopBroadcast();
    }
}
