// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {RoomKey} from "src/RoomKey.sol";

contract RoomKeyTest is Test {
    RoomKey public instance;
    string public constant ROOM_KEY_NAME = "RoomKey";
    string public constant ROOM_KEY_SYMBOL = "RK";

    function setUp() public {
        address initialOwner = vm.addr(1);
        address creatorFeeRecipient = vm.addr(2);
        address devFeeRecipient = vm.addr(3);
        address tradingPoolFeeRecipient = vm.addr(4);

        bytes memory initializeData = abi.encodeCall(
            RoomKey.initialize,
            (
                ROOM_KEY_NAME,
                ROOM_KEY_SYMBOL,
                initialOwner,
                creatorFeeRecipient,
                devFeeRecipient,
                tradingPoolFeeRecipient
            )
        );
        address proxy = Upgrades.deployUUPSProxy("RoomKey.sol", initializeData);
        instance = RoomKey(proxy);
    }

    function testName() public view {
        assertEq(instance.name(), ROOM_KEY_NAME);
    }

    function testSymbol() public view {
        assertEq(instance.symbol(), ROOM_KEY_SYMBOL);
    }
}
