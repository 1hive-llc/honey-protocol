// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockTarget} from "../src/mocks/MockTarget.sol";
import {StakeRegistry} from "../src/staking/StakeRegistry.sol";
import {StakeContext} from "../src/staking/StakeContext.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {StakeWeightStrategy} from "../src/court/StakeWeightStrategy.sol";
import {HoneyCourtMVP} from "../src/court/HoneyCourtMVP.sol";
import {OptimisticExecutor} from "../src/optimistic/OptimisticExecutor.sol";

contract OptimisticExecutorHoneyCourtTest is Test {
    MockERC20 token;
    StakeRegistry stakeRegistry;
    IdentityRegistry identityRegistry;
    StakeWeightStrategy weightStrategy;
    HoneyCourtMVP court;
    OptimisticExecutor executor;
    MockTarget target;

    address owner = address(this);
    address submitter = address(0xA11CE);
    address challenger = address(0xB0B);
    address escalator = address(0xCAFE);

    uint256 constant ACTION_BOND = 10 ether;
    uint256 constant ESCALATION_BOND = 5 ether;
    uint64 constant CHALLENGE_DURATION = 1 days;
    uint64 constant RESPONSE_DURATION = 1 days;
    uint64 constant EXECUTION_WINDOW = 3 days;

    function setUp() public {
        token = new MockERC20("Stake Token", "STK");
        stakeRegistry = new StakeRegistry(token, owner);
        identityRegistry = new IdentityRegistry(owner);
        weightStrategy = new StakeWeightStrategy();
        court = new HoneyCourtMVP(stakeRegistry, identityRegistry, weightStrategy, ESCALATION_BOND, owner);
        executor = new OptimisticExecutor(owner);
        target = new MockTarget();

        stakeRegistry.setManager(address(court), true);
        executor.createAgreement(
            token,
            court,
            ACTION_BOND,
            ACTION_BOND,
            CHALLENGE_DURATION,
            RESPONSE_DURATION,
            EXECUTION_WINDOW,
            "ipfs://agreement"
        );

        _fundApproveAndDeposit(submitter, 100 ether);
        _fundApproveAndDeposit(challenger, 100 ether);
        _fundApproveAndDeposit(escalator, 100 ether);
    }

    function testOptimisticExecutorResolutionPausesDuringHumanEscalation() public {
        uint256 actionId = _scheduleAndDisputeAction();
        (,,,,,,,,, uint256 disputeId) = executor.getAction(actionId);

        court.ruleStakeCourt(disputeId, 1);
        vm.prank(escalator);
        court.escalateToHumanCourt(disputeId);

        vm.expectRevert(OptimisticExecutor.RulingNotReady.selector);
        executor.resolve(actionId);
        assertEq(stakeRegistry.lockedBalanceOf(escalator, StakeContext.ESCALATION_BOND), ESCALATION_BOND);

        court.ruleHumanCourt(disputeId, 1, false, address(0));
        executor.resolve(actionId);

        vm.warp(block.timestamp + CHALLENGE_DURATION + 1);
        executor.execute(actionId);
        assertEq(target.value(), 42);
        assertEq(stakeRegistry.lockedBalanceOf(escalator, StakeContext.ESCALATION_BOND), 0);
    }

    function testHumanEscalationCanRejectOptimisticActionAndSlashEscalationBond() public {
        uint256 actionId = _scheduleAndDisputeAction();
        (,,,,,,,,, uint256 disputeId) = executor.getAction(actionId);

        court.ruleStakeCourt(disputeId, 1);
        vm.prank(escalator);
        court.escalateToHumanCourt(disputeId);
        court.ruleHumanCourt(disputeId, 2, true, challenger);

        executor.resolve(actionId);

        vm.expectRevert(OptimisticExecutor.NotExecutable.selector);
        executor.execute(actionId);
        assertEq(target.value(), 0);
        assertEq(token.balanceOf(challenger), 115 ether); // wallet balance after deposit plus action bonds and escalation slash
    }

    function _scheduleAndDisputeAction() internal returns (uint256 actionId) {
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(MockTarget.setValue, (42));

        vm.prank(submitter);
        actionId = executor.scheduleAction(1, targets, values, calldatas, "ipfs://action");

        vm.prank(challenger);
        executor.challengeAction(actionId, 0, "ipfs://challenge");

        vm.prank(submitter);
        executor.disputeAction(actionId, "ipfs://defense");
    }

    function _fundApproveAndDeposit(address account, uint256 amount) internal {
        token.mint(account, amount * 2);
        vm.startPrank(account);
        token.approve(address(executor), type(uint256).max);
        token.approve(address(stakeRegistry), type(uint256).max);
        stakeRegistry.deposit(amount);
        vm.stopPrank();
    }
}
