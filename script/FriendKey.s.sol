// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendStake} from "src/FriendStake.sol";

contract FriendKeyScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);
        uint256 DEV_FEE_PERCENT = 200;
        uint256 CREATOR_FEE_PERCENT = 200;
        uint256 TRADING_POOL_FEE_PERCENT = 600;
        uint256 DEV_PERFORMANCE_FEE_PERCENT = 500;
        uint256 CREATOR_PERFORMANCE_FEE_PERCENT = 1500;
        address tradingPoolFeeDestination = 0x035150F7A00479b29Df75fEb9B07892251c4E5e7;
        address devFeeDestination = initialOwner;
        address usdc = 0xC2d95a27116A694565eb14c14A2ae332FFF54e0A;
        address AUTHORITY = 0xe18b241E97793C05d7dF05d0C1a3Dec8ac08586D;

        // Deploy FriendStake beacon
        address friendStakeBeacon = Upgrades.deployBeacon("FriendStake.sol", initialOwner);

        bytes memory initializeData = abi.encodeCall(
            FriendKey.initialize,
            (
                initialOwner,
                devFeeDestination,
                DEV_FEE_PERCENT,
                CREATOR_FEE_PERCENT,
                tradingPoolFeeDestination,
                TRADING_POOL_FEE_PERCENT,
                DEV_PERFORMANCE_FEE_PERCENT,
                CREATOR_PERFORMANCE_FEE_PERCENT,
                address(usdc),
                friendStakeBeacon,
                AUTHORITY,
                1 days
            )
        );
        address proxy = Upgrades.deployUUPSProxy("FriendKey.sol", initializeData);
        FriendKey instance = FriendKey(proxy);
        console2.log("Proxy deployed to %s", address(instance));
        vm.stopBroadcast();
    }
}
