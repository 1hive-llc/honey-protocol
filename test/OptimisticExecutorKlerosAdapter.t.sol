// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20 as KlerosIERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {KlerosCore_TestBase} from "../vendor/kleros-v2/contracts/test/foundry/KlerosCore_TestBase.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockTarget} from "../src/mocks/MockTarget.sol";
import {OptimisticExecutor} from "../src/optimistic/OptimisticExecutor.sol";
import {
    IKlerosCoreForOptimisticAdapter,
    KlerosOptimisticArbitratorAdapter
} from "../src/optimistic/KlerosOptimisticArbitratorAdapter.sol";

contract OptimisticExecutorKlerosAdapterTest is KlerosCore_TestBase {
    uint96 constant GENERAL_COURT_ID = 1;
    uint256 constant DEFAULT_JURORS = 3;
    uint256 constant CLASSIC_DK = 1;

    MockERC20 bondToken;
    MockTarget target;
    OptimisticExecutor executor;
    KlerosOptimisticArbitratorAdapter adapter;

    uint96 humanCourt;
    uint96 automationCourt;
    uint256 actionBond = 10 ether;
    address submitter = address(0xA11CE);
    address challenger = address(0xB0B);

    function setUp() public override {
        super.setUp();

        humanCourt = GENERAL_COURT_ID;
        automationCourt = _createStandardCourt(humanCourt, minStake, alpha, feeForJuror, jurorsForCourtJump);
        bondToken = new MockERC20("Bond", "BOND");

        bytes memory automationExtraData = abi.encodePacked(uint256(automationCourt), DEFAULT_JURORS, CLASSIC_DK);
        adapter = new KlerosOptimisticArbitratorAdapter(
            IKlerosCoreForOptimisticAdapter(address(core)), bondToken, automationExtraData, 1 days, owner
        );
        vm.prank(owner);
        ratesConverter.changeCurrencyRates(KlerosIERC20(address(bondToken)), uint64(0.01 ether), 18);
        vm.prank(owner);
        core.changeAcceptedFeeTokens(KlerosIERC20(address(bondToken)), true);
        bondToken.mint(address(adapter), 100 ether);

        executor = new OptimisticExecutor(owner);
        target = new MockTarget();

        vm.prank(owner);
        executor.createAgreement(bondToken, adapter, actionBond, actionBond, 1 days, 1 days, 3 days, "ipfs://agreement");

        _fundAndApprove(submitter, 100 ether);
        _fundAndApprove(challenger, 100 ether);

        vm.prank(staker1);
        core.setStake(automationCourt, minStake * 10);
    }

    function testExecutorResolvesAfterNativeKlerosAutomationRulingFinalityDelay() public {
        uint256 actionId = _scheduleChallengeAndDispute();
        (,,,,,,,,, uint256 localDisputeId) = executor.getAction(actionId);
        assertEq(localDisputeId, 0);

        _drawVoteAndExecuteKlerosRuling(0, 1);

        vm.expectRevert(OptimisticExecutor.RulingNotReady.selector);
        executor.resolve(actionId);

        vm.warp(block.timestamp + 1 days);
        executor.resolve(actionId);
        vm.warp(block.timestamp + 1 days + 1);
        executor.execute(actionId);
        assertEq(target.value(), 42);
    }

    function _scheduleChallengeAndDispute() internal returns (uint256 actionId) {
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

    function _drawVoteAndExecuteKlerosRuling(uint256 klerosDisputeId, uint256 ruling) internal {
        vm.warp(block.timestamp + minStakingTime);
        sortitionModule.passPhase();
        vm.warp(block.timestamp + rngLookahead);
        sortitionModule.passPhase();
        core.draw(klerosDisputeId, DEFAULT_JURORS);

        vm.warp(block.timestamp + timesPerPeriod[0]);
        core.passPeriod(klerosDisputeId);

        uint256[] memory voteIDs = new uint256[](DEFAULT_JURORS);
        for (uint256 i = 0; i < voteIDs.length; i++) {
            voteIDs[i] = i;
        }
        vm.prank(staker1);
        disputeKit.castVote(klerosDisputeId, voteIDs, ruling, 0, "Honey executor adapter ruling");

        core.passPeriod(klerosDisputeId);
        vm.warp(block.timestamp + timesPerPeriod[3]);
        core.passPeriod(klerosDisputeId);
        core.executeRuling(klerosDisputeId);
    }

    function _fundAndApprove(address account, uint256 amount) internal {
        bondToken.mint(account, amount);
        vm.startPrank(account);
        bondToken.approve(address(executor), type(uint256).max);
        bondToken.approve(address(adapter), type(uint256).max);
        vm.stopPrank();
    }
}
