// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {RoomKey} from "src/RoomKey.sol";

contract RoomKeyTest is Test {
  RoomKey public instance;

  function setUp() public {
    address initialOwner = vm.addr(1);
    address proxy = Upgrades.deployUUPSProxy(
      "RoomKey.sol",
      abi.encodeCall(RoomKey.initialize, (initialOwner))
    );
    instance = RoomKey(proxy);
  }

  function testName() public view {
    assertEq(instance.name(), "RoomKey");
  }
}
