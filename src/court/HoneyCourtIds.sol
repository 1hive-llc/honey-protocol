// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Canonical court IDs for the initial Kleros-derived Honey v2 hierarchy.
library HoneyCourtIds {
    // Final IDs are assigned by the Kleros fork deployment. These constants document
    // the intended hierarchy for tests/config and should be updated if deployment order changes.
    uint96 internal constant GENERAL_COURT = 1;
    uint96 internal constant HUMAN_COURT = 1;
    uint96 internal constant STAKE_COURT = 2; // Automation subcourt.
}
