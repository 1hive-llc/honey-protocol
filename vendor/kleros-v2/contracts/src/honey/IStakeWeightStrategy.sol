// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Resolves a wallet to its canonical, currently verified identity; zero means ineligible.
interface IStakeIdentity {
    function stakeIdentity(address account) external view returns (address);
}

/// @notice Transforms selection weight, never token accounting.
interface IStakeWeightStrategy {
    function effectiveStake(uint96 courtId, address identity, uint256 rawActiveStake) external view returns (uint256);
    function usesIdentityWeight(uint96 courtId) external view returns (bool);
    function identityOf(address account) external view returns (address);
}
