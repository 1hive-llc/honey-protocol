// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20 as KlerosIERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {KlerosCore_TestBase} from "../vendor/kleros-v2/contracts/test/foundry/KlerosCore_TestBase.sol";
import {ContentChallengeManager} from "../src/content/ContentChallengeManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StakeRegistry} from "../src/staking/StakeRegistry.sol";
import {
    IKlerosCoreForOptimisticAdapter,
    KlerosOptimisticArbitratorAdapter
} from "../src/optimistic/KlerosOptimisticArbitratorAdapter.sol";

contract ContentChallengeKlerosE2ETest is KlerosCore_TestBase {
    uint96 constant GENERAL_COURT_ID = 1;
    uint256 constant DEFAULT_JURORS = 3;
    uint256 constant CLASSIC_DK = 1;

    MockERC20 hny;
    StakeRegistry stakeRegistry;
    KlerosOptimisticArbitratorAdapter adapter;
    ContentChallengeManager manager;

    uint96 humanCourt;
    uint96 automationCourt;
    address challenger = address(0xB0B);
    address respondent = address(0xCAFE);
    address supporter = address(0xDAD);
    address treasury = address(0x777);
    uint256 sideTarget = 100 ether;

    function setUp() public override {
        super.setUp();
        humanCourt = GENERAL_COURT_ID;
        automationCourt = _createStandardCourt(humanCourt, minStake, alpha, feeForJuror, jurorsForCourtJump);

        hny = new MockERC20("Honey", "HNY");
        stakeRegistry = new StakeRegistry(hny, owner);
        bytes memory automationExtraData = abi.encodePacked(uint256(automationCourt), DEFAULT_JURORS, CLASSIC_DK);
        adapter = new KlerosOptimisticArbitratorAdapter(
            IKlerosCoreForOptimisticAdapter(address(core)), hny, automationExtraData, 1 days, owner
        );
        manager = new ContentChallengeManager(stakeRegistry, adapter, treasury, sideTarget, 48 hours, owner);

        vm.startPrank(owner);
        ratesConverter.changeCurrencyRates(KlerosIERC20(address(hny)), uint64(0.01 ether), 18);
        core.changeAcceptedFeeTokens(KlerosIERC20(address(hny)), true);
        stakeRegistry.setManager(address(manager), true);
        vm.stopPrank();

        _fundAndDeposit(challenger, 1_000 ether);
        _fundAndDeposit(supporter, 1_000 ether);

        vm.prank(staker1);
        core.setStake(automationCourt, minStake * 10);
    }

    function testContentChallengeCreatesNativeKlerosDisputeAndSettlesRemoveRuling() public {
        vm.prank(challenger);
        uint256 challengeId =
            manager.openChallenge(keccak256("post:1"), keccak256("case:1"), respondent, "ipfs://challenge");
        vm.prank(supporter);
        manager.fundRestore(challengeId, sideTarget, "ipfs://restore");

        uint256 cost = adapter.arbitrationCost();
        manager.createDispute(challengeId, "ipfs://dispute");
        assertEq(hny.balanceOf(address(adapter)), 0, "adapter should spend fee immediately into Kleros core");
        assertEq(hny.balanceOf(address(core)), cost, "core received arbitration fee");

        _drawVoteAndExecuteKlerosRuling(0, 1);
        vm.expectRevert(ContentChallengeManager.DisputeNotRuled.selector);
        manager.executeRuling(challengeId);

        vm.warp(block.timestamp + 1 days);
        uint256 before = hny.balanceOf(challenger);
        manager.executeRuling(challengeId);
        assertGt(hny.balanceOf(challenger), before, "remove-side winner received restore remainder reward");
        (,,,,, ContentChallengeManager.Status status,,,, uint256 ruling) = manager.challenges(challengeId);
        assertEq(uint256(status), uint256(ContentChallengeManager.Status.Settled));
        assertEq(ruling, 1);
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
        disputeKit.castVote(klerosDisputeId, voteIDs, ruling, 0, "Content challenge ruling");

        core.passPeriod(klerosDisputeId);
        vm.warp(block.timestamp + timesPerPeriod[3]);
        core.passPeriod(klerosDisputeId);
        core.executeRuling(klerosDisputeId);
    }

    function _fundAndDeposit(address account, uint256 amount) internal {
        hny.mint(account, amount);
        vm.startPrank(account);
        hny.approve(address(stakeRegistry), type(uint256).max);
        stakeRegistry.deposit(amount);
        vm.stopPrank();
    }
}
