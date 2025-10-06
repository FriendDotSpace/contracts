// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendPool} from "src/FriendPool.sol";

contract SetPoolDispatcherScript is Script {
    address constant POOL = 0x346E34dD169383f0aFfc3a0D0C28Ee3D9B8d8c4E;
    address constant BACKEND_ACC = 0xe18b241E97793C05d7dF05d0C1a3Dec8ac08586D;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FriendPool instance = FriendPool(POOL);

        // assert that the trading pool fee destination is set correctly
        instance.setDispatcher(BACKEND_ACC);

        vm.stopBroadcast();
    }
}
