// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MockBridge} from "src/mocks/MockBridge.sol";

contract MockBridgeScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);

        // Deploy MockBridge contract
        MockBridge mockBridge = new MockBridge(initialOwner);

        console2.log("MockBridge deployed to %s", address(mockBridge));
        console2.log("Initial owner set to %s", initialOwner);
        console2.log("Global fixed native fee: %s wei", mockBridge.globalFixedNativeFee());
        console2.log("Global transfer fee BPS: %s", mockBridge.globalTransferFeeBps());

        vm.stopBroadcast();
    }
}
