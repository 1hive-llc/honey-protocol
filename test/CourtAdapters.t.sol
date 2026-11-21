// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {IdentityDelegationRegistry} from "../src/identity/IdentityDelegationRegistry.sol";
import {IdentityRegistryEligibility} from "../src/court/IdentityRegistryEligibility.sol";
import {HoneyCourtIds} from "../src/court/HoneyCourtIds.sol";
import {StakeWeightStrategy} from "../src/court/StakeWeightStrategy.sol";

contract CourtAdaptersTest is Test {
    address owner = address(this);
    address root = address(0xA11CE);
    address delegate = address(0xBEEF);

    function testIdentityRegistryEligibilityAllowsVerifiedRootAndDelegateInVerifiedCourts() public {
        IdentityRegistry registry = new IdentityRegistry(owner);
        IdentityDelegationRegistry delegation = new IdentityDelegationRegistry();
        IdentityRegistryEligibility eligibility =
            new IdentityRegistryEligibility(registry, delegation, HoneyCourtIds.HUMAN_COURT, HoneyCourtIds.STAKE_COURT);

        assertFalse(eligibility.isEligible(root, HoneyCourtIds.HUMAN_COURT));
        assertFalse(eligibility.isEligible(delegate, HoneyCourtIds.STAKE_COURT));

        address[] memory accounts = new address[](1);
        accounts[0] = root;
        registry.verifyIdentity(root, accounts);

        assertTrue(eligibility.isEligible(root, HoneyCourtIds.HUMAN_COURT));
        assertTrue(eligibility.isEligible(root, HoneyCourtIds.STAKE_COURT));
        assertFalse(eligibility.isEligible(root, 99));

        vm.prank(root);
        delegation.setDelegate(delegate, true);

        assertTrue(eligibility.isEligible(delegate, HoneyCourtIds.HUMAN_COURT));
        assertTrue(eligibility.isEligible(delegate, HoneyCourtIds.STAKE_COURT));
    }

    function testDelegationCanBeRevokedByRootOrDelegate() public {
        IdentityDelegationRegistry delegation = new IdentityDelegationRegistry();

        vm.prank(root);
        delegation.setDelegate(delegate, true);
        assertEq(delegation.identityRootOf(delegate), root);

        vm.prank(delegate);
        delegation.renounceDelegation();
        assertEq(delegation.identityRootOf(delegate), delegate);

        vm.prank(root);
        delegation.setDelegate(delegate, true);
        vm.prank(root);
        delegation.setDelegate(delegate, false);
        assertEq(delegation.identityRootOf(delegate), delegate);
    }

    function testStakeWeightStrategyUsesSqrtForVerifiedCourts() public {
        StakeWeightStrategy strategy = new StakeWeightStrategy();

        assertEq(strategy.effectiveStake(HoneyCourtIds.STAKE_COURT, delegate, 10_000), 100);
        assertEq(strategy.effectiveStake(HoneyCourtIds.HUMAN_COURT, delegate, 10_000), 100);
        assertEq(strategy.effectiveStake(99, delegate, 10_000), 10_000);
    }
}
