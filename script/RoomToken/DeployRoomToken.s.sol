// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {RoomRecipientRegistry} from "../../src/roomtoken/RoomRecipientRegistry.sol";
import {RoomTokenFactory, LaunchConfig} from "../../src/roomtoken/RoomTokenFactory.sol";

/// Deploys registry + factory and appends config #0. All addresses come from
/// env vars so the same script serves testnet and (post-audit) mainnet:
///   ROOMTOKEN_OWNER              platform Safe (or deployer EOA on testnet)
///   ROOMTOKEN_AUTHORITY          backend authority signer address
///   ROOMTOKEN_OPERATOR           keeper EOA
///   ROOMTOKEN_QUOTE              USDG address for this chain
///   ROOMTOKEN_NPM                pinned NonfungiblePositionManager
///   ROOMTOKEN_SWAP_ROUTER        pinned SwapRouter
///   ROOMTOKEN_V3_FACTORY         pinned UniswapV3Factory
///   ROOMTOKEN_DEFAULT_PLATFORM   default platform fee recipient
///   ROOMTOKEN_APPEND_CONFIG0     bool, defaults true. Whether this script's
///                                own broadcast appends config #0 inline.
///                                Testnet: leave true (default) — the deployer
///                                key IS the owner, so it can broadcast the
///                                append itself. Mainnet: set false — the
///                                owner is the platform Safe, which cannot
///                                sign a `vm.startBroadcast()` EOA tx; the
///                                Safe appends config #0 via its own
///                                multisig transaction after this script runs.
///                                `owner == msg.sender` is NOT a safe proxy for
///                                this decision: Foundry's DefaultSender means
///                                msg.sender inside a non-broadcast context is
///                                a constant unrelated to who will end up
///                                broadcasting.
contract DeployRoomToken is Script {
    function run() external {
        address owner = vm.envAddress("ROOMTOKEN_OWNER");
        address authority = vm.envAddress("ROOMTOKEN_AUTHORITY");
        address operator = vm.envAddress("ROOMTOKEN_OPERATOR");
        address quote = vm.envAddress("ROOMTOKEN_QUOTE");
        address npm = vm.envAddress("ROOMTOKEN_NPM");
        address router = vm.envAddress("ROOMTOKEN_SWAP_ROUTER");
        address v3Factory = vm.envAddress("ROOMTOKEN_V3_FACTORY");
        address defaultPlatform = vm.envAddress("ROOMTOKEN_DEFAULT_PLATFORM");
        bool appendConfig0 = vm.envOr("ROOMTOKEN_APPEND_CONFIG0", true);

        vm.startBroadcast();
        RoomRecipientRegistry registry = new RoomRecipientRegistry(owner, defaultPlatform);
        RoomTokenFactory factory =
            new RoomTokenFactory(owner, authority, operator, quote, npm, router, v3Factory, address(registry));
        vm.stopBroadcast();

        console.log("registry:", address(registry));
        console.log("factory:", address(factory));
        if (appendConfig0) {
            vm.startBroadcast();
            factory.appendConfig(
                LaunchConfig({
                    launchFeeQuote: 1_000_000,
                    creatorBps: 6000,
                    roomFundBps: 2500,
                    platformBps: 1500,
                    initTick: 400600,
                    capWindowSecs: 300,
                    walletCapBps: 500,
                    devBuyCapBps: 1000,
                    minCountdownSecs: 900,
                    maxCountdownSecs: 86400,
                    cardinalityTarget: 700,
                    twapWindowSecs: 60,
                    maxConversionDeviationBps: 200,
                    maxConversionImpactBps: 100
                })
            );
            vm.stopBroadcast();
            console.log("config #0 appended");
        } else {
            console.log(
                "NOTE: ROOMTOKEN_APPEND_CONFIG0=false; config #0 was NOT appended."
                " The owner (Safe) must append it via its own transaction."
            );
        }
    }
}
