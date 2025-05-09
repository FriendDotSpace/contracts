// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";

contract RoomKeyScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);
        uint256 DEV_FEE_PERCENT = 400;
        uint256 CREATOR_FEE_PERCENT = 400;
        uint256 TRADING_POOL_FEE_PERCENT = 400;
        address tradingPoolFeeDestination = address(0);
        address devFeeDestination = initialOwner;
        address mockUsdc = address(0x0);

        bytes memory initializeData = abi.encodeCall(
            FriendKey.initialize,
            (
                initialOwner,
                devFeeDestination,
                DEV_FEE_PERCENT,
                CREATOR_FEE_PERCENT,
                tradingPoolFeeDestination,
                TRADING_POOL_FEE_PERCENT,
                address(mockUsdc)
            )
        );
        address proxy = Upgrades.deployUUPSProxy("FriendKey.sol", initializeData);
        FriendKey instance = FriendKey(proxy);
        console2.log("Proxy deployed to %s", address(instance));
        vm.stopBroadcast();
    }
}
