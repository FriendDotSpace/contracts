// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library IterableMapping {
    // Iterable mapping from address to stake;
    struct Stake {
        uint256 amount;
        uint256 timestamp; // block.timestamp when staked
    }

    struct Map {
        address[] keys;
        mapping(address => Stake[]) values;
        mapping(address => uint256) indexOf;
        mapping(address => bool) inserted;
    }

    function get(Map storage map, address key) internal view returns (Stake[] storage) {
        return map.values[key];
    }

    function getEligibleStake(Map storage map, address key, uint256 timestamp) internal view returns (uint256) {
        require(map.inserted[key], "Key does not exist");
        Stake[] storage stakes = map.values[key];
        require(stakes.length > 0, "No stakes for this key");
        // Sum the stakes that are eligible for withdrawal
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < stakes.length; i++) {
            if (stakes[i].timestamp + 1 days <= timestamp) {
                totalAmount += stakes[i].amount;
            }
        }
        return totalAmount;
    }

    function getTotalStake(Map storage map, address key) internal view returns (uint256) {
        require(map.inserted[key], "Key does not exist");
        Stake[] storage stakes = map.values[key];
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < stakes.length; i++) {
            totalAmount += stakes[i].amount;
        }
        return totalAmount;
    }

    function getKeyAtIndex(Map storage map, uint256 index) internal view returns (address) {
        return map.keys[index];
    }

    function getIndexOfKey(Map storage map, address key) internal view returns (uint256) {
        return map.indexOf[key];
    }

    function size(Map storage map) internal view returns (uint256) {
        return map.keys.length;
    }

    // function set(Map storage map, address key, Stake[] calldata val) internal {
    //     if (map.inserted[key]) {
    //         map.values[key] = val;
    //     } else {
    //         map.inserted[key] = true;
    //         map.values[key] = val;
    //         map.indexOf[key] = map.keys.length;
    //         map.keys.push(key);
    //     }
    // }

    function append(Map storage map, address key, Stake memory val) internal {
        if (map.inserted[key]) {
            map.values[key].push(val);
        } else {
            map.inserted[key] = true;
            map.values[key] = new Stake[](1);
            map.values[key][0] = val;
            map.indexOf[key] = map.keys.length;
            map.keys.push(key);
        }
    }

    function pop(Map storage map, address key) internal returns (Stake memory) {
        require(map.inserted[key], "Key does not exist");
        Stake memory lastValue = map.values[key][map.values[key].length - 1];
        map.values[key].pop();
        if (map.values[key].length == 0) {
            remove(map, key);
        }
        return lastValue;
    }

    function remove(Map storage map, address key) internal {
        if (!map.inserted[key]) {
            return;
        }

        delete map.inserted[key];
        delete map.values[key];

        uint256 index = map.indexOf[key];
        address lastKey = map.keys[map.keys.length - 1];

        map.indexOf[lastKey] = index;
        delete map.indexOf[key];

        map.keys[index] = lastKey;
        map.keys.pop();
    }
}
