// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIdentityRegistry} from "../identity/IIdentityRegistry.sol";
import {IIdentityDelegationRegistry} from "../identity/IIdentityDelegationRegistry.sol";

/// @notice Kleros-v2-compatible court eligibility predicate backed by identity roots and delegates.
/// @dev A direct verified identity root is eligible. A hot/operator key is eligible when delegated by
///      a verified root. The predicate is intended for both the human court and its automation subcourt.
contract IdentityRegistryEligibility {
    IIdentityRegistry public immutable identityRegistry;
    IIdentityDelegationRegistry public immutable delegationRegistry;
    uint96 public immutable humanCourtId;
    uint96 public immutable automationCourtId;

    constructor(
        IIdentityRegistry identityRegistry_,
        IIdentityDelegationRegistry delegationRegistry_,
        uint96 humanCourtId_,
        uint96 automationCourtId_
    ) {
        identityRegistry = identityRegistry_;
        delegationRegistry = delegationRegistry_;
        humanCourtId = humanCourtId_;
        automationCourtId = automationCourtId_;
    }

    function isEligible(address juror, uint96 courtId) external view returns (bool) {
        if (courtId != humanCourtId && courtId != automationCourtId) return false;
        return stakeIdentity(juror) != address(0);
    }

    /// @notice Canonical ID, including registry-linked accounts and delegated wallets.
    function stakeIdentity(address juror) public view returns (address) {
        address root = address(delegationRegistry) == address(0) ? juror : delegationRegistry.identityRootOf(juror);
        return identityRegistry.isVerified(root) ? identityRegistry.uniqueUserId(root) : address(0);
    }
}
