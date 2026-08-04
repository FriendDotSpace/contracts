// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

/// @title Router token swapping functionality
/// @notice Minimal vendored subset of ISwapRouter from the uniswap v3-periphery 1.4.4
/// npm package, re-pragma'd. Signature and struct field order copied verbatim.
interface ISwapRouterMinimal {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    /// @dev Vendored from PeripheryImmutableState (parent of the real SwapRouter);
    /// not in the upstream ISwapRouter.sol minimal signature set, added so the
    /// factory can validate the pinned router against the pinned V3 factory.
    /// @return Returns the address of the Uniswap V3 factory
    function factory() external view returns (address);
}
