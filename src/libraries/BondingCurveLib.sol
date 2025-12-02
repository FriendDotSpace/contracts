// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Errors} from "./Errors.sol";

/**
 * @title BondingCurveLib
 * @notice Library containing bonding curve calculations for social token pricing
 * @dev This library provides pure mathematical functions for calculating token prices
 *      using polynomial bonding curves. The pricing formula uses sum of squares:
 *      price = (sum of squares * priceUnit) / divisor
 */
library BondingCurveLib {
    /**
     * @notice Calculates the price for a given supply and amount using bonding curve formula
     * @dev Uses polynomial pricing: price = (sum of squares * priceUnit) / divisor
     *      Formula: sum of i^2 from (supply) to (supply + amount - 1)
     * @param supply Current token supply
     * @param amount Number of tokens to price
     * @param divisor Divisor used for the pricing curve (affects steepness)
     * @param priceUnit Price unit based on bonding token decimals (e.g., 10^6 for USDC)
     * @return The calculated price in bonding token units
     */
    function getPrice(uint256 supply, uint256 amount, uint256 divisor, uint256 priceUnit)
        internal
        pure
        returns (uint256)
    {
        if (divisor == 0) revert Errors.ZeroDivisor();

        // Calculate sum of squares from 0 to (supply-1)
        uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;

        // Calculate sum of squares from 0 to (supply + amount - 1)
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : ((supply + amount - 1) * (supply + amount) * (2 * (supply + amount - 1) + 1)) / 6;

        // The price is the difference between the two sums
        uint256 summation = sum2 - sum1;

        return (summation * priceUnit) / divisor;
    }

    /**
     * @notice Calculates the price to buy a specific amount of tokens (before fees)
     * @param currentSupply Current total supply of the token
     * @param amount Number of tokens to buy
     * @param divisor Divisor for the bonding curve
     * @param priceUnit Price unit based on bonding token decimals
     * @return The price in bonding token units before fees
     */
    function getBuyPrice(uint256 currentSupply, uint256 amount, uint256 divisor, uint256 priceUnit)
        internal
        pure
        returns (uint256)
    {
        return getPrice(currentSupply, amount, divisor, priceUnit);
    }

    /**
     * @notice Calculates the price to sell a specific amount of tokens (before fees)
     * @param currentSupply Current total supply of the token
     * @param amount Number of tokens to sell
     * @param divisor Divisor for the bonding curve
     * @param priceUnit Price unit based on bonding token decimals
     * @return The price in bonding token units before fees
     */
    function getSellPrice(uint256 currentSupply, uint256 amount, uint256 divisor, uint256 priceUnit)
        internal
        pure
        returns (uint256)
    {
        return getPrice(currentSupply - amount, amount, divisor, priceUnit);
    }

    /**
     * @notice Calculates fees for a given price
     * @param price The base price before fees
     * @param devFeePercent Development fee percentage in basis points
     * @param creatorFeePercent Creator fee percentage in basis points
     * @param tradingPoolFeePercent Trading pool fee percentage in basis points
     * @param bpsScale Basis points scale (typically 10000)
     * @return devFee The calculated development fee
     * @return creatorFee The calculated creator fee
     * @return tradingPoolFee The calculated trading pool fee
     */
    function calculateFees(
        uint256 price,
        uint256 devFeePercent,
        uint256 creatorFeePercent,
        uint256 tradingPoolFeePercent,
        uint256 bpsScale
    ) internal pure returns (uint256 devFee, uint256 creatorFee, uint256 tradingPoolFee) {
        devFee = (price * devFeePercent) / bpsScale;
        creatorFee = (price * creatorFeePercent) / bpsScale;
        tradingPoolFee = (price * tradingPoolFeePercent) / bpsScale;
    }

    /**
     * @notice Calculates the total cost to buy tokens including all fees
     * @param currentSupply Current total supply of the token
     * @param amount Number of tokens to buy
     * @param divisor Divisor for the bonding curve
     * @param priceUnit Price unit based on bonding token decimals
     * @param devFeePercent Development fee percentage in basis points
     * @param creatorFeePercent Creator fee percentage in basis points
     * @param tradingPoolFeePercent Trading pool fee percentage in basis points
     * @param bpsScale Basis points scale (typically 10000)
     * @return The total cost including base price and all fees
     */
    function getBuyPriceAfterFee(
        uint256 currentSupply,
        uint256 amount,
        uint256 divisor,
        uint256 priceUnit,
        uint256 devFeePercent,
        uint256 creatorFeePercent,
        uint256 tradingPoolFeePercent,
        uint256 bpsScale
    ) internal pure returns (uint256) {
        uint256 price = getBuyPrice(currentSupply, amount, divisor, priceUnit);
        (uint256 devFee, uint256 creatorFee, uint256 tradingPoolFee) =
            calculateFees(price, devFeePercent, creatorFeePercent, tradingPoolFeePercent, bpsScale);
        return price + devFee + creatorFee + tradingPoolFee;
    }

    /**
     * @notice Calculates the proceeds from selling tokens after deducting all fees
     * @param currentSupply Current total supply of the token
     * @param amount Number of tokens to sell
     * @param divisor Divisor for the bonding curve
     * @param priceUnit Price unit based on bonding token decimals
     * @param devFeePercent Development fee percentage in basis points
     * @param creatorFeePercent Creator fee percentage in basis points
     * @param tradingPoolFeePercent Trading pool fee percentage in basis points
     * @param bpsScale Basis points scale (typically 10000)
     * @return The net proceeds after deducting all fees
     */
    function getSellPriceAfterFee(
        uint256 currentSupply,
        uint256 amount,
        uint256 divisor,
        uint256 priceUnit,
        uint256 devFeePercent,
        uint256 creatorFeePercent,
        uint256 tradingPoolFeePercent,
        uint256 bpsScale
    ) internal pure returns (uint256) {
        uint256 price = getSellPrice(currentSupply, amount, divisor, priceUnit);
        (uint256 devFee, uint256 creatorFee, uint256 tradingPoolFee) =
            calculateFees(price, devFeePercent, creatorFeePercent, tradingPoolFeePercent, bpsScale);
        uint256 totalFees = devFee + creatorFee + tradingPoolFee;
        return price > totalFees ? price - totalFees : 0;
    }
}
