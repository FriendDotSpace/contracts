// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FriendKey} from "src/FriendKey.sol";

contract SetPoolScript is Script {
    address constant POOL = 0x346E34dD169383f0aFfc3a0D0C28Ee3D9B8d8c4E;
    address constant PROXY = 0x1F773125477E1DbC1b2C9ce43eAd596c648e4324;


    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        FriendKey instance = FriendKey(PROXY);

        // assert that the trading pool fee destination is set correctly
        vm.assertEq(instance.tradingPoolFeeDestination(), initialOwner);

        instance.setTradingPoolFeeDestination(POOL);
        
        vm.stopBroadcast();
    }
}
