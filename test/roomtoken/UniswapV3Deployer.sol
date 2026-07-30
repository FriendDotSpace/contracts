// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

/// Deploys the real Uniswap V3 stack from pinned official artifacts so tests
/// exercise genuine pool/NPM/router behavior — never mocks.
contract UniswapV3Deployer is Test {
    function deployAll() internal returns (address factory, address weth9, address npm, address router) {
        weth9 = deployCode("test/artifacts/WETH9.json");
        factory = deployCode("test/artifacts/UniswapV3Factory.json");
        npm = deployCode("test/artifacts/NonfungiblePositionManager.json", abi.encode(factory, weth9, address(0)));
        router = deployCode("test/artifacts/SwapRouter.json", abi.encode(factory, weth9));
    }
}

interface IUniswapV3FactoryMinimal {
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
}

contract UniswapV3DeployerTest is UniswapV3Deployer {
    function test_deployAll_wiresRealV3Stack() public {
        (address factory, address weth9, address npm, address router) = deployAll();

        assertTrue(factory != address(0), "factory not deployed");
        assertTrue(weth9 != address(0), "weth9 not deployed");
        assertTrue(npm != address(0), "npm not deployed");
        assertTrue(router != address(0), "router not deployed");

        assertEq(IUniswapV3FactoryMinimal(factory).feeAmountTickSpacing(10000), 200);
    }
}
