// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {KlerosCore_TestBase} from "../vendor/kleros-v2/contracts/test/foundry/KlerosCore_TestBase.sol";
import {KlerosCore} from "../vendor/kleros-v2/contracts/src/arbitration/KlerosCore.sol";
import {DisputeKitClassic} from "../vendor/kleros-v2/contracts/src/arbitration/dispute-kits/DisputeKitClassic.sol";
import {ArbitrableExample} from "../vendor/kleros-v2/contracts/src/arbitration/arbitrables/ArbitrableExample.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

import {KlerosAgreementAdapter, IKlerosAgreementCore} from "../src/optimistic/KlerosAgreementAdapter.sol";
import {IERC20 as HoneyToken} from "../src/token/IERC20.sol";

// Exercises Agreement's fee/approval/evidence/resolve call sequence, not its full Aragon app.
contract AgreementBridgeHarness {
    KlerosAgreementAdapter public adapter;

    function configure(KlerosAgreementAdapter value) external {
        require(address(adapter) == address(0));
        adapter = value;
    }

    function dispute() external returns (uint256 id) {
        (address recipient, HoneyToken token, uint256 fee) = adapter.getDisputeFees();
        require(token.transferFrom(msg.sender, address(this), fee));
        require(token.approve(recipient, fee));
        id = adapter.createDispute(2, "agreement action");
        adapter.submitEvidence(id, msg.sender, "submitter evidence");
    }

    function resolve(uint256 id) external view returns (address subject, uint256 ruling) {
        return adapter.rule(id);
    }
}

contract HoneyAppealsTest is KlerosCore_TestBase {
    MockERC20 honey;
    ArbitrableExample honeyArbitrable;

    function setUp() public override {
        super.setUp();
        honey = new MockERC20("Honey", "HNY");
        vm.startPrank(owner);
        core.changePinakion(IERC20(address(honey)));
        core.changeAcceptedFeeTokens(IERC20(address(honey)), true);
        ratesConverter.changeCurrencyRates(IERC20(address(honey)), uint64(0.01 ether), 18);
        vm.stopPrank();
        address[4] memory accounts = [staker1, disputer, crowdfunder1, crowdfunder2];
        for (uint256 i; i < accounts.length; ++i) {
            honey.mint(accounts[i], 100_000 ether);
            vm.startPrank(accounts[i]);
            honey.approve(address(core), type(uint256).max);
            honey.approve(address(disputeKit), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _open(uint96 court) internal {
        bytes memory extra = abi.encode(court, uint256(3), uint256(1));
        honeyArbitrable =
            new ArbitrableExample(core, templateData, templateDataMappings, extra, registry, IERC20(address(honey)));
        vm.startPrank(disputer);
        honey.approve(address(honeyArbitrable), 9 ether);
        honeyArbitrable.createDispute("Honey appeal", 9 ether);
        vm.stopPrank();
        vm.prank(staker1);
        core.setStake(court, 10_000 ether);
        vm.warp(block.timestamp + minStakingTime);
        sortitionModule.passPhase();
        vm.warp(block.timestamp + rngLookahead);
        sortitionModule.passPhase();
        _vote(0);
    }

    function _vote(uint256 round) internal {
        uint256 count = core.getNumberOfVotes(0, round);
        core.draw(0, count);
        vm.warp(block.timestamp + timesPerPeriod[0]);
        core.passPeriod(0);
        uint256[] memory ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = i;
        }
        vm.prank(staker1);
        disputeKit.castVote(0, ids, 2, 0, "evidence");
        core.passPeriod(0);
    }

    function _fundBoth() internal {
        vm.prank(crowdfunder1);
        disputeKit.fundAppealWithToken(0, 1, 63 ether);
        vm.prank(crowdfunder2);
        disputeKit.fundAppealWithToken(0, 2, 42 ether);
    }

    function testAgreementBridgeThroughRealKlerosAppealAndRuling() public {
        AgreementBridgeHarness agreement = new AgreementBridgeHarness();
        KlerosAgreementAdapter adapter = new KlerosAgreementAdapter(
            IKlerosAgreementCore(address(core)),
            HoneyToken(address(honey)),
            address(agreement),
            abi.encode(uint96(1), uint256(3), uint256(1))
        );
        agreement.configure(adapter);
        vm.startPrank(disputer);
        honey.approve(address(agreement), 9 ether);
        uint256 id = agreement.dispute();
        vm.stopPrank();
        assertEq(honey.balanceOf(address(adapter)), 0);
        vm.expectRevert();
        agreement.resolve(id);
        vm.prank(staker1);
        core.setStake(1, 10_000 ether);
        vm.warp(block.timestamp + minStakingTime);
        sortitionModule.passPhase();
        vm.warp(block.timestamp + rngLookahead);
        sortitionModule.passPhase();
        _vote(0);
        _fundBoth();
        _vote(1);
        vm.warp(block.timestamp + timesPerPeriod[3]);
        core.passPeriod(0);
        // Passing into execution alone does not deliver the final callback.
        vm.expectRevert();
        agreement.resolve(id);
        core.executeRuling(0);
        (address subject, uint256 ruling) = agreement.resolve(id);
        assertEq(subject, address(agreement));
        assertEq(ruling, 4); // Kleros choice 2 means submitter, not Agreement's refused outcome 2.
    }

    function testHoneyPartialFundingAndUnsuccessfulRefund() public {
        _open(1);
        uint256 before = honey.balanceOf(crowdfunder1);
        uint256 nativeBefore = crowdfunder1.balance;
        vm.prank(crowdfunder1);
        disputeKit.fundAppealWithToken(0, 1, 10 ether);
        assertEq(honey.balanceOf(crowdfunder1), before - 10 ether);
        vm.warp(block.timestamp + timesPerPeriod[3]);
        core.passPeriod(0);
        assertEq(disputeKit.withdrawFeesAndRewards(0, payable(crowdfunder1), 1), 10 ether);
        assertEq(honey.balanceOf(crowdfunder1), before);
        assertEq(crowdfunder1.balance, nativeBefore);
        assertEq(disputeKit.withdrawFeesAndRewards(0, payable(crowdfunder1), 1), 0);
    }

    function testHoneyExcessIsNotPulledAndAppealRewardsStayHoney() public {
        _open(1);
        assertEq(core.appealCostInFeeToken(0), 21 ether);
        uint256 before = honey.balanceOf(crowdfunder1);
        vm.prank(crowdfunder1);
        disputeKit.fundAppealWithToken(0, 1, 1000 ether);
        assertEq(honey.balanceOf(crowdfunder1), before - 63 ether);
        vm.prank(crowdfunder2);
        disputeKit.fundAppealWithToken(0, 2, 42 ether);
        KlerosCore.Round memory round = core.getRoundInfo(0, 1);
        assertEq(address(round.feeToken), address(honey));
        assertEq(round.totalFeesForJurors, 21 ether);
        assertEq(round.nbVotes, 7);
        assertEq(honey.balanceOf(address(disputeKit)), 84 ether);
        _vote(1);
        vm.warp(block.timestamp + timesPerPeriod[3]);
        core.passPeriod(0);
        uint256 beforeWinner = honey.balanceOf(crowdfunder2);
        assertEq(disputeKit.withdrawFeesAndRewards(0, payable(crowdfunder2), 2), 84 ether);
        assertEq(honey.balanceOf(crowdfunder2), beforeWinner + 84 ether);
        assertEq(disputeKit.withdrawFeesAndRewards(0, payable(crowdfunder1), 1), 0);
        uint256 jurorBefore = honey.balanceOf(staker1);
        core.execute(0, 0, 100);
        core.execute(0, 1, 100);
        assertEq(honey.balanceOf(staker1), jurorBefore + 30 ether);
        core.executeRuling(0);
        assertEq(address(core).balance, 0);
        assertEq(address(disputeKit).balance, 0);
    }

    function testHoneyCourtJumpPreservesCurrency() public {
        uint96 child = _createStandardCourt(1, minStake, alpha, feeForJuror, 3);
        _open(child);
        _fundBoth();
        (uint96 currentCourt,,,,) = core.disputes(0);
        assertEq(currentCourt, 1);
        assertEq(address(core.getRoundInfo(0, 1).feeToken), address(honey));
        assertEq(core.getNumberOfRounds(0), 2);
        _vote(1);
        vm.warp(block.timestamp + timesPerPeriod[3]);
        core.passPeriod(0);
        assertEq(disputeKit.withdrawFeesAndRewards(0, payable(crowdfunder2), 2), 84 ether);
        core.execute(0, 0, 100);
        core.execute(0, 1, 100);
        core.executeRuling(0);
        assertEq(honey.balanceOf(address(disputeKit)), 0);
    }

    function testTokenFundingCannotEnterNativeDispute() public {
        vm.prank(disputer);
        arbitrable.createDispute{value: 0.09 ether}("native");
        vm.prank(crowdfunder1);
        vm.expectRevert();
        disputeKit.fundAppealWithToken(0, 1, 63 ether);
        assertEq(honey.balanceOf(address(disputeKit)), 0);
    }

    function testPausedWithdrawalPreservesClaim() public {
        _open(1);
        vm.prank(crowdfunder1);
        disputeKit.fundAppealWithToken(0, 1, 10 ether);
        vm.warp(block.timestamp + timesPerPeriod[3]);
        core.passPeriod(0);
        vm.prank(owner);
        core.pause();
        vm.expectRevert();
        disputeKit.withdrawFeesAndRewards(0, payable(crowdfunder1), 1);
        assertEq(honey.balanceOf(address(disputeKit)), 10 ether);
        vm.prank(owner);
        core.unpause();
        assertEq(disputeKit.withdrawFeesAndRewards(0, payable(crowdfunder1), 1), 10 ether);
    }

    function testNativeFundingCannotMixWithHoney() public {
        _open(1);
        vm.prank(crowdfunder1);
        vm.expectRevert();
        disputeKit.fundAppeal{value: 1 ether}(0, 1);
        vm.deal(address(disputeKit), 1 ether);
        vm.prank(address(disputeKit));
        vm.expectRevert();
        core.appeal{value: 1 ether}(0, 2, arbitratorExtraData);
    }

    function testMissingAllowanceAndExpiredFundingRevertWithoutAccounting() public {
        _open(1);
        vm.startPrank(crowdfunder1);
        honey.approve(address(disputeKit), 0);
        vm.expectRevert();
        disputeKit.fundAppealWithToken(0, 1, 10 ether);
        vm.stopPrank();
        assertEq(honey.balanceOf(address(disputeKit)), 0);
        vm.warp(block.timestamp + timesPerPeriod[3]);
        vm.expectRevert();
        disputeKit.fundAppealWithToken(0, 1, 0);
    }
}
