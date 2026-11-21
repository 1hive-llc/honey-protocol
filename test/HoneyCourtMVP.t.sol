// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StakeRegistry} from "../src/staking/StakeRegistry.sol";
import {StakeContext} from "../src/staking/StakeContext.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {HoneyCourtMVP} from "../src/court/HoneyCourtMVP.sol";
import {HoneyCourtIds} from "../src/court/HoneyCourtIds.sol";
import {StakeWeightStrategy} from "../src/court/StakeWeightStrategy.sol";

contract HoneyCourtMVPTest is Test {
    MockERC20 token;
    StakeRegistry stakeRegistry;
    IdentityRegistry identityRegistry;
    StakeWeightStrategy weightStrategy;
    HoneyCourtMVP court;

    address owner = address(this);
    address unverified = address(0xBAD);
    address human = address(0xBEEF);
    address escalator = address(0xCAFE);
    address recipient = address(0xDAD);

    uint256 constant ESCALATION_BOND = 10 ether;

    function setUp() public {
        token = new MockERC20("Stake Token", "STK");
        stakeRegistry = new StakeRegistry(token, owner);
        identityRegistry = new IdentityRegistry(owner);
        weightStrategy = new StakeWeightStrategy();
        court = new HoneyCourtMVP(stakeRegistry, identityRegistry, weightStrategy, ESCALATION_BOND, owner);

        stakeRegistry.setManager(address(court), true);

        _fundAndDeposit(unverified, 1_000 ether);
        _fundAndDeposit(human, 1_000 ether);
        _fundAndDeposit(escalator, 1_000 ether);

        address[] memory accounts = new address[](1);
        accounts[0] = human;
        identityRegistry.verifyIdentity(human, accounts);
    }

    function testStakeCourtUsesSqrtWeight() public {
        vm.prank(unverified);
        court.activateStake(HoneyCourtIds.STAKE_COURT, 100 ether);

        assertEq(court.activeStake(unverified, HoneyCourtIds.STAKE_COURT), 100 ether);
        assertEq(court.effectiveStake(unverified, HoneyCourtIds.STAKE_COURT), 10_000_000_000);
        assertEq(stakeRegistry.lockedBalanceOf(unverified, StakeContext.STAKE_COURT_ACTIVE), 100 ether);
    }

    function testHumanCourtRequiresVerificationAndUsesSqrtWeight() public {
        vm.prank(unverified);
        vm.expectRevert(HoneyCourtMVP.HumanCourtRequiresVerification.selector);
        court.activateStake(HoneyCourtIds.HUMAN_COURT, 10_000 ether);

        vm.prank(human);
        court.activateStake(HoneyCourtIds.HUMAN_COURT, 10_000);

        assertEq(court.activeStake(human, HoneyCourtIds.HUMAN_COURT), 10_000);
        assertEq(court.effectiveStake(human, HoneyCourtIds.HUMAN_COURT), 100);
        assertEq(stakeRegistry.lockedBalanceOf(human, StakeContext.HUMAN_COURT_ACTIVE), 10_000);
    }

    function testDeactivateStakeReleasesContextLock() public {
        vm.startPrank(unverified);
        court.activateStake(HoneyCourtIds.STAKE_COURT, 100 ether);
        court.deactivateStake(HoneyCourtIds.STAKE_COURT, 40 ether);
        vm.stopPrank();

        assertEq(court.activeStake(unverified, HoneyCourtIds.STAKE_COURT), 60 ether);
        assertEq(stakeRegistry.lockedBalanceOf(unverified, StakeContext.STAKE_COURT_ACTIVE), 60 ether);
    }

    function testStakeCourtRulingCanBeEscalatedAndPausesRulingUntilHumanDecision() public {
        vm.prank(unverified);
        uint256 disputeId = court.createDispute(2, abi.encode("optimistic-action"));

        court.ruleStakeCourt(disputeId, 2);
        (bool ruled, uint256 ruling) = court.getRuling(disputeId);
        assertTrue(ruled);
        assertEq(ruling, 2);

        vm.prank(escalator);
        court.escalateToHumanCourt(disputeId);

        (ruled, ruling) = court.getRuling(disputeId);
        assertFalse(ruled);
        assertEq(ruling, 0);
        assertEq(stakeRegistry.lockedBalanceOf(escalator, StakeContext.ESCALATION_BOND), ESCALATION_BOND);

        court.ruleHumanCourt(disputeId, 1, false, address(0));

        (ruled, ruling) = court.getRuling(disputeId);
        assertTrue(ruled);
        assertEq(ruling, 1);
        assertEq(stakeRegistry.lockedBalanceOf(escalator, StakeContext.ESCALATION_BOND), 0);
    }

    function testFrivolousEscalationCanSlashEscalationBond() public {
        vm.prank(unverified);
        uint256 disputeId = court.createDispute(2, abi.encode("optimistic-action"));
        court.ruleStakeCourt(disputeId, 1);

        vm.prank(escalator);
        court.escalateToHumanCourt(disputeId);

        court.ruleHumanCourt(disputeId, 1, true, recipient);

        assertEq(stakeRegistry.lockedBalanceOf(escalator, StakeContext.ESCALATION_BOND), 0);
        assertEq(stakeRegistry.totalBalanceOf(escalator), 990 ether);
        assertEq(token.balanceOf(recipient), ESCALATION_BOND);
    }

    function testCannotEscalateBeforeStakeCourtRuling() public {
        vm.prank(unverified);
        uint256 disputeId = court.createDispute(2, abi.encode("optimistic-action"));

        vm.prank(escalator);
        vm.expectRevert(HoneyCourtMVP.InvalidStatus.selector);
        court.escalateToHumanCourt(disputeId);
    }

    function _fundAndDeposit(address account, uint256 amount) internal {
        token.mint(account, amount);
        vm.startPrank(account);
        token.approve(address(stakeRegistry), type(uint256).max);
        stakeRegistry.deposit(amount);
        vm.stopPrank();
    }
}
