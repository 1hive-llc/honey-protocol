// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Canonical staking/bond contexts for the generic ERC20 StakeRegistry ledger.
library StakeContext {
    bytes32 internal constant IDENTITY_BOND = keccak256("honey-v2.stake-context.identity-bond");
    bytes32 internal constant HUMAN_COURT_ACTIVE = keccak256("honey-v2.stake-context.human-court-active");
    bytes32 internal constant STAKE_COURT_ACTIVE = keccak256("honey-v2.stake-context.stake-court-active");
    bytes32 internal constant NODE_QUEUE_ACTIVE = keccak256("honey-v2.stake-context.node-queue-active");
    bytes32 internal constant REGISTRY_CHALLENGE_BOND = keccak256("honey-v2.stake-context.registry-challenge-bond");
    bytes32 internal constant REGISTRY_RESPONSE_BOND = keccak256("honey-v2.stake-context.registry-response-bond");
    bytes32 internal constant ESCALATION_BOND = keccak256("honey-v2.stake-context.escalation-bond");
    bytes32 internal constant OPTIMISTIC_EXECUTION_BOND = keccak256("honey-v2.stake-context.optimistic-execution-bond");
    bytes32 internal constant CONTENT_CHALLENGE = keccak256("honey-v2.stake-context.content-challenge");
}
