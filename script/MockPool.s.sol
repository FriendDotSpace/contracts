// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockPool} from "src/MockPool.sol";

contract MockPoolScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);

        // Base mainnet addresses
        address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address dlnSource = 0xeF4fB24aD0916217251F553c0596F8Edc630EB66;

        bytes memory initializeData = abi.encodeCall(MockPool.initialize, (initialOwner, usdc, dlnSource));
        address proxy = Upgrades.deployUUPSProxy("MockPool.sol", initializeData);
        MockPool instance = MockPool(proxy);
        console2.log("Proxy deployed to %s", address(instance));
        vm.stopBroadcast();
    }
}
