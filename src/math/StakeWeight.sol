// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Effective stake weight helpers for Honey v2 court contexts.
library StakeWeight {
    enum Mode {
        Linear,
        SquareRoot
    }

    function effectiveWeight(uint256 rawStake, Mode mode) internal pure returns (uint256) {
        if (mode == Mode.Linear) return rawStake;
        if (mode == Mode.SquareRoot) return sqrt(rawStake);
        revert("STAKE_WEIGHT_UNKNOWN_MODE");
    }

    /// @notice Integer square root rounded down.
    function sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;

        uint256 y = x;
        z = 1;

        if (y >= 2 ** 128) {
            y >>= 128;
            z <<= 64;
        }
        if (y >= 2 ** 64) {
            y >>= 64;
            z <<= 32;
        }
        if (y >= 2 ** 32) {
            y >>= 32;
            z <<= 16;
        }
        if (y >= 2 ** 16) {
            y >>= 16;
            z <<= 8;
        }
        if (y >= 2 ** 8) {
            y >>= 8;
            z <<= 4;
        }
        if (y >= 2 ** 4) {
            y >>= 4;
            z <<= 2;
        }
        if (y >= 2 ** 2) z <<= 1;

        // Seven Babylonian iterations are enough for uint256 after the initial estimate.
        unchecked {
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            uint256 z1 = x / z;
            return z < z1 ? z : z1;
        }
    }
}
