// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

interface IBeacon {
    function implementation() external view returns (address);
}

/// @notice Detects bytecode drift between locally compiled contracts and on-chain deployments.
///         Uses a tiered comparison: function selectors → bytecode length → fuzzy bytecode match.
///         Contracts marked synced=false in the deployment registry are skipped.
contract BytecodeDriftTest is Test {
    bytes32 constant ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // CBOR metadata prefix used by Solidity compiler
    bytes8 constant CBOR_PREFIX = hex"a264697066735822";

    struct ContractInfo {
        string name;
        string artifactName;
        address proxyOrBeacon;
        bool isBeacon;
        bool synced;
    }

    string json;
    ContractInfo[] contracts;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"));
        json = vm.readFile("deployments/base-mainnet.json");

        // FriendKey (UUPS)
        contracts.push(
            ContractInfo({
                name: "FriendKey",
                artifactName: vm.parseJsonString(json, ".contracts.FriendKey.artifact"),
                proxyOrBeacon: vm.parseJsonAddress(json, ".contracts.FriendKey.proxy"),
                isBeacon: false,
                synced: vm.parseJsonBool(json, ".contracts.FriendKey.synced")
            })
        );

        // FriendStake (Beacon)
        contracts.push(
            ContractInfo({
                name: "FriendStake",
                artifactName: vm.parseJsonString(json, ".contracts.FriendStake.artifact"),
                proxyOrBeacon: vm.parseJsonAddress(json, ".contracts.FriendStake.beacon"),
                isBeacon: true,
                synced: vm.parseJsonBool(json, ".contracts.FriendStake.synced")
            })
        );

        // FriendPool (UUPS)
        contracts.push(
            ContractInfo({
                name: "FriendPool",
                artifactName: vm.parseJsonString(json, ".contracts.FriendPool.artifact"),
                proxyOrBeacon: vm.parseJsonAddress(json, ".contracts.FriendPool.proxy"),
                isBeacon: false,
                synced: vm.parseJsonBool(json, ".contracts.FriendPool.synced")
            })
        );

        // FriendRoomManager (UUPS)
        contracts.push(
            ContractInfo({
                name: "FriendRoomManager",
                artifactName: vm.parseJsonString(json, ".contracts.FriendRoomManager.artifact"),
                proxyOrBeacon: vm.parseJsonAddress(json, ".contracts.FriendRoomManager.proxy"),
                isBeacon: false,
                synced: vm.parseJsonBool(json, ".contracts.FriendRoomManager.synced")
            })
        );
    }

    function test_allContracts_bytecodeDrift() public {
        for (uint256 i = 0; i < contracts.length; i++) {
            ContractInfo memory c = contracts[i];

            if (!c.synced) {
                // solhint-disable-next-line no-console
                emit log(string.concat("SKIPPED: ", c.name, " marked as not synced"));
                continue;
            }

            // Get on-chain implementation address
            address onChainImpl;
            if (c.isBeacon) {
                onChainImpl = IBeacon(c.proxyOrBeacon).implementation();
            } else {
                bytes32 raw = vm.load(c.proxyOrBeacon, ERC1967_IMPL_SLOT);
                onChainImpl = address(uint160(uint256(raw)));
            }
            require(onChainImpl != address(0), string.concat(c.name, ": implementation is zero address"));

            bytes memory onChainCode = onChainImpl.code;
            bytes memory localCode = vm.getDeployedCode(c.artifactName);

            // Tier 1: Selector comparison
            _compareSelectors(c.name, onChainCode, localCode);

            // Tier 2: Length comparison
            _compareLength(c.name, onChainCode, localCode);

            // Tier 3: Fuzzy bytecode comparison (strip metadata)
            _compareBytecode(c.name, onChainCode, localCode);
        }
    }

    /// @dev Extract and compare function selectors from bytecode dispatch tables.
    ///      Selectors are 4-byte values following PUSH4 (0x63) opcodes in the dispatch section.
    function _compareSelectors(string memory name, bytes memory onChain, bytes memory local) internal pure {
        bytes memory onChainSelectors = _extractSelectors(onChain);
        bytes memory localSelectors = _extractSelectors(local);

        assertEq(
            keccak256(onChainSelectors),
            keccak256(localSelectors),
            string.concat(name, ": function selectors differ - functions may have been added or removed")
        );
    }

    /// @dev Compare bytecode lengths. Allow small differences from immutables/metadata.
    function _compareLength(string memory name, bytes memory onChain, bytes memory local) internal pure {
        uint256 onChainLen = onChain.length;
        uint256 localLen = local.length;
        uint256 diff = onChainLen > localLen ? onChainLen - localLen : localLen - onChainLen;
        uint256 maxLen = onChainLen > localLen ? onChainLen : localLen;

        // Allow up to 2% or 200 bytes difference (metadata/immutable variance)
        uint256 threshold = maxLen * 2 / 100;
        if (threshold < 200) threshold = 200;

        assertLe(
            diff,
            threshold,
            string.concat(name, ": bytecode length differs significantly (>2% or >200 bytes)")
        );
    }

    /// @dev Strip CBOR metadata suffix and compare remaining bytecode.
    ///      Allows small byte-level differences from immutables (e.g., EIP-712 address).
    function _compareBytecode(string memory name, bytes memory onChain, bytes memory local) internal pure {
        bytes memory onChainStripped = _stripMetadata(onChain);
        bytes memory localStripped = _stripMetadata(local);

        // Compare the shorter of the two (metadata stripping may not be perfect)
        uint256 compareLen = onChainStripped.length < localStripped.length
            ? onChainStripped.length
            : localStripped.length;

        if (compareLen == 0) return;

        uint256 diffCount = 0;
        for (uint256 i = 0; i < compareLen; i++) {
            if (onChainStripped[i] != localStripped[i]) {
                diffCount++;
            }
        }

        // Allow up to 0.5% byte differences (immutables like address(this) in EIP-712)
        uint256 maxDiffs = compareLen * 5 / 1000;
        if (maxDiffs < 40) maxDiffs = 40; // At least 40 bytes (one address = 20 bytes, could appear twice)

        assertLe(
            diffCount,
            maxDiffs,
            string.concat(name, ": bytecode differs beyond immutable/metadata tolerance (>0.5%)")
        );
    }

    /// @dev Extract PUSH4 selectors from the first 4KB of bytecode (dispatch table region).
    ///      Returns sorted concatenated selectors for deterministic comparison.
    function _extractSelectors(bytes memory code) internal pure returns (bytes memory) {
        // Scan first 4KB for PUSH4 (0x63) opcodes
        uint256 scanLen = code.length < 4096 ? code.length : 4096;
        bytes4[] memory selectors = new bytes4[](128); // max 128 selectors
        uint256 count = 0;

        for (uint256 i = 0; i < scanLen - 4; i++) {
            if (uint8(code[i]) == 0x63 && count < 128) {
                bytes4 sel = bytes4(code[i + 1]) | (bytes4(code[i + 2]) >> 8) | (bytes4(code[i + 3]) >> 16)
                    | (bytes4(code[i + 4]) >> 24);
                // Filter out unlikely selectors (all zeros, all ones)
                if (sel != bytes4(0) && sel != bytes4(type(uint32).max)) {
                    // Check for duplicates
                    bool dup = false;
                    for (uint256 j = 0; j < count; j++) {
                        if (selectors[j] == sel) {
                            dup = true;
                            break;
                        }
                    }
                    if (!dup) {
                        selectors[count] = sel;
                        count++;
                    }
                }
            }
        }

        // Sort selectors for deterministic comparison
        for (uint256 i = 0; i < count; i++) {
            for (uint256 j = i + 1; j < count; j++) {
                if (uint32(selectors[i]) > uint32(selectors[j])) {
                    bytes4 tmp = selectors[i];
                    selectors[i] = selectors[j];
                    selectors[j] = tmp;
                }
            }
        }

        // Pack into bytes
        bytes memory result = new bytes(count * 4);
        for (uint256 i = 0; i < count; i++) {
            result[i * 4] = selectors[i][0];
            result[i * 4 + 1] = selectors[i][1];
            result[i * 4 + 2] = selectors[i][2];
            result[i * 4 + 3] = selectors[i][3];
        }
        return result;
    }

    /// @dev Strip CBOR-encoded metadata from the end of bytecode.
    ///      Solidity appends a CBOR payload starting with 0xa264697066735822.
    function _stripMetadata(bytes memory code) internal pure returns (bytes memory) {
        if (code.length < 53) return code; // Too short to have metadata

        // Search backwards for the CBOR prefix in the last 100 bytes
        uint256 searchStart = code.length > 100 ? code.length - 100 : 0;
        for (uint256 i = code.length - 1; i >= searchStart + 8; i--) {
            bool found = true;
            for (uint256 j = 0; j < 8; j++) {
                if (code[i - 7 + j] != CBOR_PREFIX[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                // Strip from the CBOR prefix onwards
                bytes memory stripped = new bytes(i - 7);
                for (uint256 k = 0; k < stripped.length; k++) {
                    stripped[k] = code[k];
                }
                return stripped;
            }
        }

        return code; // No metadata found
    }
}
