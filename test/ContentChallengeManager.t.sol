// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ContentChallengeManager} from "../src/content/ContentChallengeManager.sol";
import {IOptimisticArbitrator} from "../src/optimistic/IOptimisticArbitrator.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockMiniMeHoney} from "../src/mocks/MockMiniMeHoney.sol";
import {HoneyApproveAndCallAdapter} from "../src/staking/HoneyApproveAndCallAdapter.sol";
import {StakeRegistry} from "../src/staking/StakeRegistry.sol";
import {StakeContext} from "../src/staking/StakeContext.sol";

contract ContentArbitratorMock is IOptimisticArbitrator {
    uint256 public cost;
    uint256 public nextDisputeId;
    mapping(uint256 => bool) public ruled;
    mapping(uint256 => uint256) public rulings;

    event DisputeCreated(uint256 indexed disputeId, uint8 possibleRulings, bytes metadata);

    constructor(uint256 cost_) {
        cost = cost_;
    }

    function setCost(uint256 cost_) external {
        cost = cost_;
    }

    function arbitrationCost() external view returns (uint256) {
        return cost;
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

contract ContentChallengeManagerTest is Test {
    MockERC20 token;
    StakeRegistry registry;
    ContentArbitratorMock arbitrator;
    ContentChallengeManager manager;

    address owner = address(0xA11CE);
    address challenger = address(0xB0B);
    address respondent = address(0xCAFE);
    address supporterA = address(0xDAD);
    address supporterB = address(0xF00D);
    address treasury = address(0x777);

    uint256 constant TARGET = 100 ether;
    uint256 constant COST = 20 ether;
    uint64 constant RESPONSE_DURATION = 48 hours;
    bytes32 constant CONTENT_ID = keccak256("post:1");
    bytes32 constant CASE_HASH = keccak256("case:1");

    function setUp() public {
        token = new MockERC20("Honey", "HNY");
        registry = new StakeRegistry(token, owner);
        arbitrator = new ContentArbitratorMock(COST);
        manager = new ContentChallengeManager(registry, arbitrator, treasury, TARGET, RESPONSE_DURATION, owner);

        vm.prank(owner);
        registry.setManager(address(manager), true);

        _fundAndDeposit(challenger, 500 ether);
        _fundAndDeposit(respondent, 500 ether);
        _fundAndDeposit(supporterA, 500 ether);
        _fundAndDeposit(supporterB, 500 ether);
    }

    function testOpenChallengeFullyFundsRemoveSide() public {
        uint256 challengeId = _open();
        (
            bytes32 contentId,,
            address recordedChallenger,
            address recordedRespondent,
            uint64 deadline,
            ContentChallengeManager.Status status,
            uint256 removeFunded,
            uint256 restoreFunded,,
        ) = manager.challenges(challengeId);

        assertEq(contentId, CONTENT_ID);
        assertEq(recordedChallenger, challenger);
        assertEq(recordedRespondent, respondent);
        assertEq(uint256(deadline), block.timestamp + RESPONSE_DURATION);
        assertEq(uint256(status), uint256(ContentChallengeManager.Status.ResponseFunding));
        assertEq(removeFunded, TARGET);
        assertEq(restoreFunded, 0);
        assertEq(registry.lockedBalanceOf(challenger, StakeContext.CONTENT_CHALLENGE), TARGET);
    }

    function testDefaultRemoveReleasesChallengerFunds() public {
        uint256 challengeId = _open();
        vm.warp(block.timestamp + RESPONSE_DURATION + 1);
        manager.executeDefault(challengeId);

        assertEq(registry.lockedBalanceOf(challenger), 0);
        assertEq(registry.withdrawableBalanceOf(challenger), 500 ether);
        (,,,,, ContentChallengeManager.Status status,,,, uint256 ruling) = manager.challenges(challengeId);
        assertEq(uint256(status), uint256(ContentChallengeManager.Status.Defaulted));
        assertEq(ruling, 1);
    }

    function testCreateDisputeSpendsFeesHalfFromEachSide() public {
        uint256 challengeId = _open();
        _fundRestoreFull(challengeId);
        manager.createDispute(challengeId, "ipfs://dispute");

        assertEq(token.balanceOf(address(arbitrator)), COST);
        assertEq(manager.remainingContribution(challengeId, ContentChallengeManager.Side.Remove, challenger), 90 ether);
        assertEq(manager.remainingContribution(challengeId, ContentChallengeManager.Side.Restore, supporterA), 54 ether);
        assertEq(manager.remainingContribution(challengeId, ContentChallengeManager.Side.Restore, supporterB), 36 ether);
        (,,,,, ContentChallengeManager.Status status,,, uint256 localDisputeId,) = manager.challenges(challengeId);
        assertEq(uint256(status), uint256(ContentChallengeManager.Status.Disputed));
        assertEq(localDisputeId, 0);
    }

    function testRemoveRulingRewardsRemoveSideWithRestoreRemainder() public {
        uint256 challengeId = _open();
        _fundRestoreFull(challengeId);
        manager.createDispute(challengeId, "ipfs://dispute");
        arbitrator.rule(0, 1);

        uint256 before = token.balanceOf(challenger);
        manager.executeRuling(challengeId);

        assertEq(registry.lockedBalanceOf(challenger), 0);
        assertEq(registry.withdrawableBalanceOf(challenger), 490 ether); // 500 deposited - 10 fee spent.
        assertEq(token.balanceOf(challenger) - before, 90 ether); // Restore remaining slashed to winner.
        assertEq(registry.lockedBalanceOf(supporterA), 0);
        assertEq(registry.lockedBalanceOf(supporterB), 0);
    }

    function testRestoreRulingRewardsRestoreContributorsProRata() public {
        uint256 challengeId = _open();
        _fundRestoreFull(challengeId);
        manager.createDispute(challengeId, "ipfs://dispute");
        arbitrator.rule(0, 2);

        uint256 beforeA = token.balanceOf(supporterA);
        uint256 beforeB = token.balanceOf(supporterB);
        manager.executeRuling(challengeId);

        assertEq(registry.lockedBalanceOf(supporterA), 0);
        assertEq(registry.lockedBalanceOf(supporterB), 0);
        assertEq(registry.withdrawableBalanceOf(supporterA), 494 ether); // 500 - 6 fee.
        assertEq(registry.withdrawableBalanceOf(supporterB), 496 ether); // 500 - 4 fee.
        assertEq(token.balanceOf(supporterA) - beforeA, 54 ether);
        assertEq(token.balanceOf(supporterB) - beforeB, 36 ether);
        assertEq(registry.lockedBalanceOf(challenger), 0);
    }

    function testNoRulingReleasesRemainingFundsToOriginalContributors() public {
        uint256 challengeId = _open();
        _fundRestoreFull(challengeId);
        manager.createDispute(challengeId, "ipfs://dispute");
        arbitrator.rule(0, 0);
        manager.executeRuling(challengeId);

        assertEq(registry.lockedBalanceOf(challenger), 0);
        assertEq(registry.lockedBalanceOf(supporterA), 0);
        assertEq(registry.lockedBalanceOf(supporterB), 0);
        assertEq(registry.withdrawableBalanceOf(challenger), 490 ether);
        assertEq(registry.withdrawableBalanceOf(supporterA), 494 ether);
        assertEq(registry.withdrawableBalanceOf(supporterB), 496 ether);
    }

    function testCannotCreateDisputeUntilRestoreFullyFunded() public {
        uint256 challengeId = _open();
        vm.prank(supporterA);
        manager.fundRestore(challengeId, 99 ether, "ipfs://restore");
        vm.expectRevert(ContentChallengeManager.RestoreNotFunded.selector);
        manager.createDispute(challengeId, "ipfs://dispute");
    }

    function testApproveAndCallOpensChallengeWithShortfallDeposit() public {
        (
            MockMiniMeHoney hny,
            StakeRegistry miniMeRegistry,
            ContentChallengeManager miniMeManager,
            HoneyApproveAndCallAdapter adapter
        ) = _miniMeChallengeStack();

        hny.mint(challenger, TARGET);
        vm.startPrank(challenger);
        hny.approve(address(miniMeRegistry), 40 ether);
        miniMeRegistry.deposit(40 ether);
        hny.approveAndCall(
            address(adapter),
            60 ether,
            abi.encode(
                HoneyApproveAndCallAdapter.Intent.OpenContentChallenge,
                abi.encode(
                    HoneyApproveAndCallAdapter.OpenContentChallengeIntent({
                        manager: miniMeManager,
                        contentId: CONTENT_ID,
                        localCaseIdHash: CASE_HASH,
                        respondent: respondent,
                        evidenceURI: "ipfs://challenge"
                    })
                )
            )
        );
        vm.stopPrank();

        (
            ,,
            address recordedChallenger,
            address recordedRespondent,,
            ContentChallengeManager.Status status,
            uint256 removeFunded,,,
        ) = miniMeManager.challenges(1);
        assertEq(recordedChallenger, challenger);
        assertEq(recordedRespondent, respondent);
        assertEq(uint256(status), uint256(ContentChallengeManager.Status.ResponseFunding));
        assertEq(removeFunded, TARGET);
        assertEq(miniMeRegistry.totalBalanceOf(challenger), TARGET);
        assertEq(miniMeRegistry.lockedBalanceOf(challenger, StakeContext.CONTENT_CHALLENGE), TARGET);
    }

    function testApproveAndCallFundsRestoreWithShortfallDeposit() public {
        (
            MockMiniMeHoney hny,
            StakeRegistry miniMeRegistry,
            ContentChallengeManager miniMeManager,
            HoneyApproveAndCallAdapter adapter
        ) = _miniMeChallengeStack();

        hny.mint(challenger, TARGET);
        vm.startPrank(challenger);
        hny.approve(address(miniMeRegistry), TARGET);
        miniMeRegistry.deposit(TARGET);
        miniMeManager.openChallenge(CONTENT_ID, CASE_HASH, respondent, "ipfs://challenge");
        vm.stopPrank();

        hny.mint(supporterA, TARGET);
        vm.startPrank(supporterA);
        hny.approve(address(miniMeRegistry), 25 ether);
        miniMeRegistry.deposit(25 ether);
        hny.approveAndCall(
            address(adapter),
            75 ether,
            abi.encode(
                HoneyApproveAndCallAdapter.Intent.FundContentChallengeRestore,
                abi.encode(
                    HoneyApproveAndCallAdapter.FundContentChallengeRestoreIntent({
                        manager: miniMeManager,
                        challengeId: 1,
                        contributionAmount: TARGET,
                        evidenceURI: "ipfs://restore"
                    })
                )
            )
        );
        vm.stopPrank();

        (,,,,,,, uint256 restoreFunded,,) = miniMeManager.challenges(1);
        assertEq(restoreFunded, TARGET);
        assertEq(miniMeRegistry.totalBalanceOf(supporterA), TARGET);
        assertEq(miniMeRegistry.lockedBalanceOf(supporterA, StakeContext.CONTENT_CHALLENGE), TARGET);
    }

    function _open() internal returns (uint256 challengeId) {
        vm.prank(challenger);
        challengeId = manager.openChallenge(CONTENT_ID, CASE_HASH, respondent, "ipfs://challenge");
    }

    function _fundRestoreFull(uint256 challengeId) internal {
        vm.prank(supporterA);
        manager.fundRestore(challengeId, 60 ether, "ipfs://restore-a");
        vm.prank(supporterB);
        manager.fundRestore(challengeId, 40 ether, "ipfs://restore-b");
    }

    function _fundAndDeposit(address account, uint256 amount) internal {
        token.mint(account, amount);
        vm.startPrank(account);
        token.approve(address(registry), type(uint256).max);
        registry.deposit(amount);
        vm.stopPrank();
    }

    function _miniMeChallengeStack()
        internal
        returns (
            MockMiniMeHoney hny,
            StakeRegistry miniMeRegistry,
            ContentChallengeManager miniMeManager,
            HoneyApproveAndCallAdapter adapter
        )
    {
        hny = new MockMiniMeHoney("Honey", "HNY");
        miniMeRegistry = new StakeRegistry(hny, owner);
        ContentArbitratorMock miniMeArbitrator = new ContentArbitratorMock(COST);
        miniMeManager =
            new ContentChallengeManager(miniMeRegistry, miniMeArbitrator, treasury, TARGET, RESPONSE_DURATION, owner);
        adapter = new HoneyApproveAndCallAdapter(hny, miniMeRegistry);

        vm.startPrank(owner);
        miniMeRegistry.setManager(address(miniMeManager), true);
        miniMeRegistry.setManager(address(adapter), true);
        miniMeManager.setIntentExecutor(address(adapter), true);
        vm.stopPrank();
    }
}
