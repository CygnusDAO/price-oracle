// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

import "../interfaces/IERC20.sol";

/**
 * @notice This is an edited version of PRB's ERC20Normalizer contract. The original can be found here:
 *         https://github.com/paulrberg/prb-contracts/blob/main/src/token/erc20/ERC20Normalizer.sol
 *         The edit comes from the fact that we want to keep the normalize function as a view function,
 *         We removed the `computeScalar` function inside the `normalize` function and instead we just
 *         compute the scalar only once when we add the LP Tokens
 */

/// @title ERC20Normalizer
/// @author Paul Razvan Berg
abstract contract ERC20Normalizer {
    /// @notice Emitted when attempting to compute the scalar for a token whose decimals are zero.
    error IERC20Normalizer__TokenDecimalsZero(IERC20 token);

    /// @notice Emitted when attempting to compute the scalar for a token whose decimals are greater than 18.
    error IERC20Normalizer__TokenDecimalsGreaterThan18(IERC20 token, uint256 decimals);

    /// INTERNAL STORAGE ///

    /// @dev Mapping between ERC-20 tokens and their associated scalars $10^(18 - decimals)$.
    mapping(IERC20 => uint256) internal scalars;

    /// CONSTANT FUNCTIONS ///

    function getScalar(IERC20 token) internal view returns (uint256 scalar) {
        // Check if we already have a cached scalar for the given token.
        scalar = scalars[token];
    }

    /// NON-CONSTANT FUNCTIONS ///

    function computeScalar(IERC20 token) internal returns (uint256 scalar) {
        // Query the ERC-20 contract to obtain the decimals.
        uint256 decimals = uint256(token.decimals());

        // Revert if the token's decimals are zero.
        if (decimals == 0) {
            revert IERC20Normalizer__TokenDecimalsZero(token);
        }

        // Revert if the token's decimals are greater than 18.
        if (decimals > 18) {
            revert IERC20Normalizer__TokenDecimalsGreaterThan18(token, decimals);
        }

        // Calculate the scalar.
        unchecked {
            scalar = 10**(18 - decimals);
        }

        // Save the scalar in storage.
        scalars[token] = scalar;
    }

    function normalize(IERC20 token, uint256 amount) internal view returns (uint256 normalizedAmount) {
        uint256 scalar = getScalar(token);

        // Normalize the amount. We have to use checked arithmetic because the calculation can overflow uint256.
        normalizedAmount = scalar != 1 ? amount * scalar : amount;
    }
}
