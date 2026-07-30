# Pinned Uniswap V3 test artifacts

Each `*.json` in this directory is trimmed to `{ "abi": [...], "bytecode": "0x..." }` — the shape
`vm.getCode` / `deployCode` need — from the official, unmodified npm build artifacts below. No
source was recompiled; bytecode is copied verbatim from the published package tarballs.

| File | Source package | Path inside tarball |
|---|---|---|
| `UniswapV3Factory.json` | `@uniswap/v3-core@1.0.1` | `artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json` |
| `NonfungiblePositionManager.json` | `@uniswap/v3-periphery@1.4.4` | `artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json` |
| `SwapRouter.json` | `@uniswap/v3-periphery@1.4.4` | `artifacts/contracts/SwapRouter.sol/SwapRouter.json` |
| `WETH9.json` | `canonical-weth@1.4.0` | `build/contracts/WETH9.json` |

`WETH9` provenance note: neither `@uniswap/v3-core` nor `@uniswap/v3-periphery` ships a WETH9
build artifact (periphery only ships the `IWETH9` interface, used at compile time via
`INonfungiblePositionManager`/`ISwapRouter` imports elsewhere in this repo). `canonical-weth` is
the npm package published by the WETH9 deployer/maintainer team and is the artifact Uniswap's own
test suites (v2-periphery, v3-periphery hardhat tests) vendor for local WETH9 deploys. Its
`contractName` is `WETH9` and its source matches the contract deployed on Ethereum mainnet at
`0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`.

## Hashes

`bytecode` = creation code as published in the artifact (what `deployCode` sends as init code).
`deployedBytecode` = runtime code recorded here for comparison against live chain `cast code`
output per Step 5 — it is **not** stored in the trimmed JSON files, only its hash is recorded here.

| Contract | keccak256(bytecode) | keccak256(deployedBytecode) |
|---|---|---|
| UniswapV3Factory | `0xa9cb11ffa1b1bf9a9a2b70b66f6a22db3e8328b37ec44e6ce602749081efdb6d` | `0xc66c27d7d60725224552811cfb0e8148a15e914e0e31720daed102e61a0118af` |
| NonfungiblePositionManager | `0x6d4a795ab08d4b4737c563d58af66cd9c1fe56a4ff3258fec16fd7c5eeade093` | `0x3247cdc75425fff3d9842c11743e686e336762388649ab50eeb22e9365616463` |
| SwapRouter | `0x4ab2bb678b8aa5c9267d00ec2ac6e6603909f2a6c9e8c59daaaf5f4af1ba6710` | `0x00a8fe172447e3376988fc3dfb36f204f042ffb01bb0808d55d95899eff15745` |
| WETH9 | `0xe66e74ba1a282ff15770abef79456c4c1bc48b714eaf771c7b274f158051c61c` | `0xb603564c85581d9f3165facdbd3edebd05417b132ec760ce26eba226ca210458` |

Hashes computed with `cast keccak "$(jq -r '.bytecode' <file>)"` /
`cast keccak "$(jq -r '.deployedBytecode' <file>)"` against the untrimmed source artifacts
(`.bytecode`/`.deployedBytecode` fields identical to the values kept above).

Note: `NonfungiblePositionManager` and `SwapRouter` embed immutable constructor args
(`factory`, `WETH9`) directly into runtime bytecode at fixed offsets. The
`deployedBytecode` hash above is only valid for byte-for-byte comparison when those
immutables are zero (i.e. this artifact's own local deployment via `UniswapV3Deployer`,
or a chain deployment using the same factory/WETH9 addresses). For live-chain
verification (Step 5) where immutables differ, mask those slots before comparing, or
fall back to the documented alternative (Blockscout "verified, exact match" +
`factory()`/`WETH9()` cross-check).
