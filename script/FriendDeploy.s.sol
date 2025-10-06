// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FriendKey} from "src/FriendKey.sol";
import {FriendStake} from "src/FriendStake.sol";
import {FriendPool} from "src/FriendPool.sol";

contract FriendDeployScript is Script {
    address constant BACKEND_ACC = 0xe18b241E97793C05d7dF05d0C1a3Dec8ac08586D;

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
        address tradingPoolFeeDestination = initialOwner;
        address devFeeDestination = initialOwner;
        address usdc = 0xC2d95a27116A694565eb14c14A2ae332FFF54e0A;

        FriendStake friendStake = new FriendStake();

        // 1. Deploy FriendKey
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
                address(friendStake)
            )
        );
        address proxy = Upgrades.deployUUPSProxy("FriendKey.sol", initializeData);
        FriendKey friendKey = FriendKey(proxy);
        console2.log("FriendKey deployed to %s", address(friendKey));

        // 2. Deploy FriendPool
        // it's the mockBridge on sepolia and the real one on mainnet
        address dlnSource = 0xFF7D9a483d0820cc5286E37ed5184e7dBc52B6F4;
        bytes memory poolInitializeData = abi.encodeCall(FriendPool.initialize, (initialOwner, address(friendKey), dlnSource));
        address poolProxy = Upgrades.deployUUPSProxy("FriendPool.sol", poolInitializeData);
        FriendPool pool = FriendPool(poolProxy);
        console2.log("FriendPool deployed to %s", address(pool));

        // 3. Link FriendKey with FriendPool
        friendKey.setTradingPoolFeeDestination(address(pool));
        vm.assertEq(friendKey.tradingPoolFeeDestination(), address(pool));

        
        // 4. Set dispatcher in FriendPool
        pool.setDispatcher(BACKEND_ACC);
        

        vm.stopBroadcast();
    }
}
