// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOptimisticArbitrator {
    function arbitrationCost() external view returns (uint256);
    function createDispute(uint8 possibleRulings, bytes calldata metadata) external returns (uint256 disputeId);
    function submitEvidence(uint256 disputeId, address submitter, bytes calldata evidence) external;
    function getRuling(uint256 disputeId) external view returns (bool ruled, uint256 ruling);
}
