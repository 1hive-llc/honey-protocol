// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StakeRegistry} from "../src/staking/StakeRegistry.sol";
import {StakeContext} from "../src/staking/StakeContext.sol";
import {OptimisticIdentityRegistry} from "../src/identity/OptimisticIdentityRegistry.sol";
import {IOptimisticArbitrator} from "../src/optimistic/IOptimisticArbitrator.sol";
import {IIdentityRegistry} from "../src/identity/IIdentityRegistry.sol";

contract RegistryArbitratorMock is IOptimisticArbitrator {
    uint256 public nextDisputeId = 1;
    mapping(uint256 => bool) public ruled;
    mapping(uint256 => uint256) public rulings;

    event DisputeCreated(uint256 indexed disputeId, uint8 possibleRulings, bytes metadata);

    function arbitrationCost() external pure returns (uint256) {
        return 0;
    }

    function createDispute(uint8 possibleRulings, bytes calldata metadata) external returns (uint256 disputeId) {
        disputeId = nextDisputeId++;
        emit DisputeCreated(disputeId, possibleRulings, metadata);
    }

    function submitEvidence(uint256, address, bytes calldata) external {}

    function getRuling(uint256 disputeId) external view returns (bool, uint256) {
        return (ruled[disputeId], rulings[disputeId]);
    }

    function rule(uint256 disputeId, uint256 ruling) external {
        ruled[disputeId] = true;
        rulings[disputeId] = ruling;
    }
}

contract OptimisticIdentityRegistryTest is Test {
    MockERC20 token;
    StakeRegistry stakeRegistry;
    RegistryArbitratorMock arbitrator;
    OptimisticIdentityRegistry registry;

    address owner = address(0xA11CE);
    address applicant = address(0xCAFE);
    address challenger = address(0xBEEF);
    address defender = address(0xDAD);
    address member = address(0xF00D);

    uint256 constant BOND = 10 ether;
    uint64 constant CHALLENGE_DURATION = 3 days;
    uint64 constant RESPONSE_DURATION = 2 days;
    uint64 constant EXIT_DELAY = 4 days;

    function setUp() public {
        token = new MockERC20("Stake Token", "STK");
        stakeRegistry = new StakeRegistry(token, owner);
        arbitrator = new RegistryArbitratorMock();
        registry = new OptimisticIdentityRegistry(
            stakeRegistry, arbitrator, BOND, BOND, BOND, CHALLENGE_DURATION, RESPONSE_DURATION, EXIT_DELAY
        );

        vm.prank(owner);
        stakeRegistry.setManager(address(registry), true);

        _fundAndDeposit(applicant, 100 ether);
        _fundAndDeposit(challenger, 100 ether);
        _fundAndDeposit(defender, 100 ether);
        _fundAndDeposit(member, 100 ether);
    }

    function testApplicationFinalizesPermissionlesslyAndKeepsBondLocked() public {
        uint256 applicationId = _apply(applicant, "proof");

        assertFalse(registry.isVerified(applicant));
        assertEq(stakeRegistry.lockedBalanceOf(applicant, StakeContext.IDENTITY_BOND), BOND);

        vm.expectRevert(OptimisticIdentityRegistry.ChallengeWindowOpen.selector);
        registry.finalizeApplication(applicationId);

        vm.warp(block.timestamp + CHALLENGE_DURATION);
        registry.finalizeApplication(applicationId);

        assertTrue(registry.isVerified(applicant));
        assertEq(uint256(registry.statusOf(applicant)), uint256(IIdentityRegistry.IdentityStatus.Verified));
        assertEq(stakeRegistry.lockedBalanceOf(applicant, StakeContext.IDENTITY_BOND), BOND);
        assertEq(stakeRegistry.withdrawableBalanceOf(applicant), 90 ether);
    }

    function testChallengedApplicationCanBeDefendedByAnyoneAndApplicantWinVerifies() public {
        uint256 applicationId = _apply(applicant, "proof");

        vm.prank(challenger);
        uint256 disputeId = registry.challengeApplication(applicationId, keccak256("low-passport"));

        vm.prank(defender);
        registry.defendApplication(applicationId, keccak256("supporting-proof"));

        arbitrator.rule(disputeId, 1);
        registry.resolveApplication(applicationId);

        assertTrue(registry.isVerified(applicant));
        assertEq(stakeRegistry.lockedBalanceOf(applicant, StakeContext.IDENTITY_BOND), BOND);
        assertEq(stakeRegistry.lockedBalanceOf(defender, StakeContext.REGISTRY_RESPONSE_BOND), 0);
        assertEq(stakeRegistry.lockedBalanceOf(challenger, StakeContext.REGISTRY_CHALLENGE_BOND), 0);
        assertEq(token.balanceOf(defender), 10 ether); // defender received slashed challenge bond externally
        assertEq(stakeRegistry.totalBalanceOf(challenger), 90 ether);
    }

    function testChallengerWinsApplicationAndReceivesApplicationAndResponseBonds() public {
        uint256 applicationId = _apply(applicant, "proof");

        vm.prank(challenger);
        uint256 disputeId = registry.challengeApplication(applicationId, keccak256("bad-proof"));

        vm.prank(defender);
        registry.defendApplication(applicationId, keccak256("weak-defense"));

        arbitrator.rule(disputeId, 2);
        registry.resolveApplication(applicationId);

        assertFalse(registry.isVerified(applicant));
        assertEq(uint256(registry.statusOf(applicant)), uint256(IIdentityRegistry.IdentityStatus.Revoked));
        assertEq(stakeRegistry.totalBalanceOf(applicant), 90 ether);
        assertEq(stakeRegistry.totalBalanceOf(defender), 90 ether);
        assertEq(stakeRegistry.totalBalanceOf(challenger), 100 ether);
        assertEq(token.balanceOf(challenger), 20 ether);
    }

    function testApplicationDefaultIfNobodyDefends() public {
        uint256 applicationId = _apply(applicant, "proof");

        vm.prank(challenger);
        registry.challengeApplication(applicationId, keccak256("bad-proof"));

        vm.warp(block.timestamp + RESPONSE_DURATION);
        registry.claimApplicationDefault(applicationId);

        assertFalse(registry.isVerified(applicant));
        assertEq(stakeRegistry.totalBalanceOf(applicant), 90 ether);
        assertEq(stakeRegistry.totalBalanceOf(challenger), 100 ether);
        assertEq(token.balanceOf(challenger), 10 ether);
    }

    function testMemberChallengeCanBeDefendedByAnyoneAndMemberWinKeepsVerification() public {
        _verifyUnchallenged(member);

        vm.prank(challenger);
        uint256 challengeId = registry.challengeMember(member, keccak256("member-suspicious"));

        vm.prank(defender);
        uint256 disputeId = registry.defendMember(challengeId, keccak256("member-defense"));

        arbitrator.rule(disputeId, 1);
        registry.resolveMemberChallenge(challengeId);

        assertTrue(registry.isVerified(member));
        assertEq(registry.activeMemberChallengeOf(member), 0);
        assertEq(stakeRegistry.lockedBalanceOf(member, StakeContext.IDENTITY_BOND), BOND);
        assertEq(token.balanceOf(defender), 10 ether);
    }

    function testMemberChallengeDefaultRemovesAndSlashesIdentityBond() public {
        _verifyUnchallenged(member);

        vm.prank(challenger);
        uint256 challengeId = registry.challengeMember(member, keccak256("member-suspicious"));

        vm.warp(block.timestamp + RESPONSE_DURATION);
        registry.claimMemberChallengeDefault(challengeId);

        assertFalse(registry.isVerified(member));
        assertEq(uint256(registry.statusOf(member)), uint256(IIdentityRegistry.IdentityStatus.Revoked));
        assertEq(stakeRegistry.totalBalanceOf(member), 90 ether);
        assertEq(token.balanceOf(challenger), 10 ether);
    }

    function testVoluntaryExitIsDelayedAndReleasesRegistryBond() public {
        _verifyUnchallenged(member);

        vm.prank(member);
        registry.requestExit();

        vm.prank(member);
        vm.expectRevert(OptimisticIdentityRegistry.ExitWindowOpen.selector);
        registry.finalizeExit();

        vm.warp(block.timestamp + EXIT_DELAY);

        vm.prank(member);
        registry.finalizeExit();

        assertFalse(registry.isVerified(member));
        assertEq(stakeRegistry.lockedBalanceOf(member, StakeContext.IDENTITY_BOND), 0);
        assertEq(stakeRegistry.withdrawableBalanceOf(member), 100 ether);
    }

    function testExitPausedByActiveChallenge() public {
        _verifyUnchallenged(member);

        vm.prank(member);
        registry.requestExit();

        vm.prank(challenger);
        registry.challengeMember(member, keccak256("during-exit"));

        vm.warp(block.timestamp + EXIT_DELAY);

        vm.prank(member);
        vm.expectRevert(OptimisticIdentityRegistry.ActiveChallenge.selector);
        registry.finalizeExit();
    }

    function _verifyUnchallenged(address account) internal returns (uint256 applicationId) {
        applicationId = _apply(account, "proof");
        vm.warp(block.timestamp + CHALLENGE_DURATION);
        registry.finalizeApplication(applicationId);
    }

    function _apply(address account, string memory salt) internal returns (uint256 applicationId) {
        vm.prank(account);
        applicationId = registry.applyForVerification(keccak256(bytes(salt)));
    }

    function _fundAndDeposit(address account, uint256 amount) internal {
        token.mint(account, amount);
        vm.startPrank(account);
        token.approve(address(stakeRegistry), type(uint256).max);
        stakeRegistry.deposit(amount);
        vm.stopPrank();
    }
}
