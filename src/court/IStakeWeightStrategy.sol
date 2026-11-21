// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal effective-weight strategy used by the Kleros fork adaptation.
interface IStakeWeightStrategy {
    function effectiveStake(uint96 courtId, address account, uint256 rawActiveStake) external view returns (uint256);
}
