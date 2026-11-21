// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {KlerosCore_TestBase} from "../vendor/kleros-v2/contracts/test/foundry/KlerosCore_TestBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HoneyStakeWeightStrategy} from "../vendor/kleros-v2/contracts/src/honey/HoneyStakeWeightStrategy.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {IdentityDelegationRegistry} from "../src/identity/IdentityDelegationRegistry.sol";
import {IdentityRegistryEligibility} from "../src/court/IdentityRegistryEligibility.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @notice Exercises real Core token transfers, sortition and dispute-kit wallet voting.
contract HoneyIdentitySortitionTest is KlerosCore_TestBase {
    IdentityRegistry identities;
    IdentityDelegationRegistry delegates;
    HoneyStakeWeightStrategy strategy;
    MockERC20 honey;
    uint96 child;

    function setUp() public override {
        super.setUp();
        child = _createStandardCourt(1, minStake, alpha, feeForJuror, jurorsForCourtJump);
        identities = new IdentityRegistry(address(this));
        delegates = new IdentityDelegationRegistry();
        IdentityRegistryEligibility eligibility = new IdentityRegistryEligibility(identities, delegates, 1, child);
        strategy = new HoneyStakeWeightStrategy(1, child, address(eligibility));
        _verify(staker1);
        _verify(other);
        vm.prank(staker1);
        delegates.setDelegate(staker2, true);
        honey = new MockERC20("Honey", "HNY");
        vm.startPrank(owner);
        core.changePinakion(IERC20(address(honey)));
        sortitionModule.changeStakeWeightStrategy(strategy);
        vm.stopPrank();
        _fund(staker1);
        _fund(staker2);
        _fund(other);
    }

    function testSplitWalletsHaveExactlyOneIdentityWeightAndRawWithdrawals() public {
        _stake(staker1, 1, 10_000);
        _weight(1, staker1, 10_000, 100);
        _stake(staker1, 1, 5_000);
        _stake(staker2, 1, 5_000);
        _weight(1, staker1, 10_000, 100);
        (uint256 balance,, uint256 raw,) = sortitionModule.getJurorBalance(staker2, 1);
        assertEq(balance, 5_000);
        assertEq(raw, 5_000);
        assertEq(honey.balanceOf(address(core)), 10_000);
        _stake(staker1, 1, 0);
        _stake(staker2, 1, 0);
        _weight(1, staker1, 0, 0);
        assertEq(honey.balanceOf(address(core)), 0);
        assertEq(sortitionModule.totalStaked(), 0);
    }

    function testFuzzSplittingDoesNotChangeWeight(uint96 left, uint96 right) public {
        uint256 a = bound(uint256(left), 1_000, 1 ether);
        uint256 b = bound(uint256(right), 1_000, 1 ether);
        _stake(staker1, 1, a);
        _stake(staker2, 1, b);
        _weight(1, staker1, a + b, strategy.effectiveStake(1, staker1, a + b));
        _stake(staker1, 1, 0);
        _weight(1, staker1, b, strategy.effectiveStake(1, staker1, b));
    }

    function testRegistryAliasesUseCanonicalIdentity() public {
        vm.prank(staker2);
        delegates.renounceDelegation();
        identities.linkAccount(staker1, staker2);
        _stake(staker1, 1, 5_000);
        _stake(staker2, 1, 5_000);
        _weight(1, staker1, 10_000, 100);
        _weight(1, staker2, 0, 0);
    }

    function testDescendantPathsAggregateOncePerCourtAndIdentity() public {
        _stake(staker1, 1, 5_000);
        _stake(staker2, child, 5_000);
        _stake(other, child, 10_000);
        _weight(1, staker1, 10_000, 100);
        _weight(child, staker1, 5_000, 70);
        _weight(child, other, 10_000, 100);
        _stake(staker1, child, 5_000);
        _weight(1, staker1, 15_000, 122);
        _weight(child, staker1, 10_000, 100);
        vm.prank(address(core));
        sortitionModule.forcedUnstakeAllCourts(staker1);
        _weight(1, staker1, 5_000, 70);
        _weight(child, staker1, 5_000, 70);
    }

    function testRewardsAndPenaltiesUseRawStakeAndUpdateBothCourts() public {
        _stake(staker1, child, 5_000);
        _stake(staker2, child, 5_000);
        // Core transfers a reward before updating accounting.
        honey.mint(address(core), 2_100);
        vm.prank(address(core));
        assertTrue(sortitionModule.setStakeReward(staker2, child, 2_100));
        _weight(1, staker1, 12_100, 110);
        _weight(child, staker1, 12_100, 110);
        vm.prank(address(core));
        (uint256 balance, uint256 raw, uint256 penalty) = sortitionModule.setStakePenalty(staker2, child, 2_100);
        assertEq(balance, 5_000);
        assertEq(raw, 5_000);
        assertEq(penalty, 2_100);
        _weight(1, staker1, 10_000, 100);
        _weight(child, staker1, 10_000, 100);
    }

    function testPenaltyBeyondSourceStakeReducesRemainingBackedPaths() public {
        _stake(staker2, 1, 1_000);
        _stake(staker2, child, 5_000);
        vm.prank(address(core));
        (uint256 balance, uint256 raw, uint256 penalty) = sortitionModule.setStakePenalty(staker2, 1, 3_000);
        assertEq(balance, 3_000);
        assertEq(raw, 0);
        assertEq(penalty, 3_000);
        _weight(1, staker1, 3_000, 54);
        _weight(child, staker1, 3_000, 54);
        (, , uint256 remaining,) = sortitionModule.getJurorBalance(staker2, child);
        assertEq(remaining, 3_000);
        _stake(staker2, child, 0);
        assertEq(sortitionModule.totalStaked(), 0);
        // The 3,000 penalty remains in Core for redistribution.
        assertEq(honey.balanceOf(address(core)), 3_000);
    }

    function testFuzzPenaltyNeverLeavesUnbackedAggregate(uint96 aSeed, uint96 bSeed, uint96 penaltySeed) public {
        uint256 a = bound(uint256(aSeed), 1_000, 1 ether);
        uint256 b = bound(uint256(bSeed), 1_000, 1 ether);
        uint256 requested = bound(uint256(penaltySeed), 0, 2 * (a + b));
        _stake(staker2, 1, a);
        _stake(staker2, child, b);
        vm.prank(address(core));
        (uint256 balance,, uint256 penalty) = sortitionModule.setStakePenalty(staker2, 1, requested);
        (, , uint256 parentRaw,) = sortitionModule.getJurorBalance(staker2, 1);
        (, , uint256 childRaw,) = sortitionModule.getJurorBalance(staker2, child);
        assertEq(balance + penalty, a + b);
        assertEq(parentRaw + childRaw, balance);
        _weight(1, staker1, balance, strategy.effectiveStake(1, staker1, balance));
        _weight(child, staker1, childRaw, strategy.effectiveStake(child, staker1, childRaw));
    }

    function testPenaltyUsesLockedLeftoverBeforeReducingOtherPaths() public {
        _stake(staker2, 1, 5_000);
        vm.prank(address(core));
        sortitionModule.lockStake(staker2, 5_000);
        _stake(staker2, 1, 0);
        _stake(staker2, child, 5_000);
        vm.prank(address(core));
        sortitionModule.setStakePenalty(staker2, 1, 3_000);
        _weight(child, staker1, 5_000, 70);
        _weight(1, staker1, 5_000, 70);
        (uint256 balance,,,) = sortitionModule.getJurorBalance(staker2, child);
        assertEq(balance, 7_000);
    }

    function testDelegationChangeCannotMoveAnActivePosition() public {
        _stake(staker2, child, 5_000);
        vm.prank(staker2);
        delegates.renounceDelegation();
        vm.prank(other);
        delegates.setDelegate(staker2, true);
        vm.expectRevert();
        _stake(staker2, child, 6_000);
        vm.expectRevert();
        _stake(staker2, 1, 1_000);
        _weight(child, staker1, 5_000, 70);
        _weight(child, other, 0, 0);
        _stake(staker2, child, 0);
        _stake(staker2, child, 5_000);
        _weight(child, staker1, 0, 0);
        _weight(child, other, 5_000, 70);
    }

    function testLockedLeftoversPreventRebindingUntilReleased() public {
        _stake(staker2, child, 5_000);
        vm.prank(address(core));
        sortitionModule.lockStake(staker2, 2_000);
        vm.prank(staker2);
        delegates.renounceDelegation();
        vm.prank(other);
        delegates.setDelegate(staker2, true);
        _stake(staker2, child, 0);
        _weight(child, staker1, 0, 0);
        assertEq(honey.balanceOf(address(core)), 2_000);
        vm.expectRevert();
        _stake(staker2, child, 5_000);
        vm.prank(address(core));
        sortitionModule.unlockStake(staker2, 2_000);
        sortitionModule.withdrawLeftoverPNK(staker2);
        assertEq(honey.balanceOf(address(core)), 0);
        _stake(staker2, child, 5_000);
        _weight(child, other, 5_000, 70);
    }

    function testRevokedIdentityCannotBeDrawnOrIncreaseButCanExit() public {
        _stake(staker2, child, 5_000);
        identities.revokeIdentity(staker1);
        vm.expectRevert();
        _stake(staker2, child, 6_000);
        _drawing();
        for (uint256 n; n < 20; n++) {
            (address drawn,) = sortitionModule.draw(1, 0, n);
            assertEq(drawn, address(0));
        }
        _staking();
        _stake(staker2, child, 0);
        assertEq(honey.balanceOf(address(core)), 0);
    }

    function testReassignedDelegateIsNotDrawnUnderOldIdentity() public {
        _stake(staker2, child, 5_000);
        _drawing();
        vm.prank(staker2);
        delegates.renounceDelegation();
        vm.prank(other);
        delegates.setDelegate(staker2, true);
        (address drawn,) = sortitionModule.draw(1, 0, 0);
        assertEq(drawn, address(0));
    }

    function testDelayedChangesRevalidateIdentityAndPreserveOtherWallet() public {
        _stake(staker1, child, 5_000);
        _stake(staker2, child, 5_000);
        _drawing();
        _stake(staker1, child, 6_000);
        _stake(staker2, child, 6_000);
        _weight(child, staker1, 10_000, 100);
        vm.prank(staker2);
        delegates.renounceDelegation();
        _staking();
        sortitionModule.executeDelayedStakes(2);
        _weight(child, staker1, 11_000, 104);
        (, , uint256 raw,) = sortitionModule.getJurorBalance(staker2, child);
        assertEq(raw, 5_000);
        _stake(staker2, child, 0);
        _weight(child, staker1, 6_000, 77);
    }

    function testTwoStageDrawReturnsBothWalletsAndOriginalStakeCourt() public {
        _stake(staker1, child, 5_000);
        _stake(staker2, child, 5_000);
        _drawing();
        uint256 first;
        uint256 second;
        for (uint256 n; n < 100; n++) {
            (address drawn, uint96 fromCourt) = sortitionModule.draw(1, 0, n);
            assertEq(fromCourt, child);
            if (drawn == staker1) first++;
            else if (drawn == staker2) second++;
            else revert("Unexpected wallet");
        }
        assertGt(first, 0);
        assertGt(second, 0);
    }

    function testSplitDoesNotChangeWhichIdentityIsDrawn() public {
        _stake(staker1, 1, 10_000);
        _stake(other, 1, 10_000);
        _drawing();
        bool[100] memory beforeSplit;
        for (uint256 n; n < 100; n++) {
            (address drawn,) = sortitionModule.draw(1, 0, n);
            beforeSplit[n] = drawn == other;
        }
        // Use Core's immediate settlement path to keep the same RNG/phase.
        vm.prank(address(core));
        sortitionModule.setStake(staker1, 1, 0, 5_000, 5_000);
        vm.prank(address(core));
        sortitionModule.setStake(staker2, 1, 5_000, 0, 5_000);
        for (uint256 n; n < 100; n++) {
            (address drawn,) = sortitionModule.draw(1, 0, n);
            assertEq(drawn == other, beforeSplit[n]);
        }
    }

    function testPolicyCannotChangeAfterStakingEvenAfterExit() public {
        _stake(staker1, 1, 5_000);
        _stake(staker1, 1, 0);
        vm.prank(owner);
        vm.expectRevert();
        sortitionModule.changeStakeWeightStrategy(strategy);
    }

    function testCoreDrawAndVotesStillBelongToFundedWallets() public {
        _stake(staker1, child, 5_000);
        _stake(staker2, child, 5_000);
        vm.prank(disputer);
        arbitrable.createDispute{value: feeForJuror * 3}("Synthetic Honey case");
        vm.warp(block.timestamp + minStakingTime);
        sortitionModule.passPhase();
        vm.warp(block.timestamp + rngLookahead);
        sortitionModule.passPhase();
        core.draw(0, 3);
        vm.warp(block.timestamp + timesPerPeriod[0]);
        core.passPeriod(0);
        for (uint256 i; i < 3; i++) {
            (address account,,,) = disputeKit.getVoteInfo(0, 0, i);
            assertTrue(account == staker1 || account == staker2);
            uint256[] memory voteIDs = new uint256[](1);
            voteIDs[0] = i;
            vm.prank(account);
            disputeKit.castVote(0, voteIDs, 1, 0, "Synthetic vote");
        }
        core.passPeriod(0);
        vm.warp(block.timestamp + timesPerPeriod[3]);
        core.passPeriod(0);
        core.execute(0, 0, 100);
        core.executeRuling(0);
        (, uint256 locked1,,) = sortitionModule.getJurorBalance(staker1, child);
        (, uint256 locked2,,) = sortitionModule.getJurorBalance(staker2, child);
        assertEq(locked1 + locked2, 0);
        _staking();
        _stake(staker1, child, 0);
        _stake(staker2, child, 0);
        assertEq(honey.balanceOf(address(core)), 0);
    }

    function _verify(address root) internal {
        address[] memory accounts = new address[](1);
        accounts[0] = root;
        identities.verifyIdentity(root, accounts);
    }

    function _fund(address wallet) internal {
        honey.mint(wallet, 10 ether);
        vm.prank(wallet);
        honey.approve(address(core), type(uint256).max);
    }

    function _stake(address wallet, uint96 court, uint256 amount) internal {
        vm.prank(wallet);
        core.setStake(court, amount);
    }

    function _weight(uint96 court, address identity, uint256 raw, uint256 weight) internal view {
        (uint256 actualRaw, uint256 actualWeight) = sortitionModule.getIdentityStake(court, identity);
        assertEq(actualRaw, raw);
        assertEq(actualWeight, weight);
    }

    function _drawing() internal {
        vm.prank(address(core));
        sortitionModule.createDisputeHook(0, 0);
        vm.warp(block.timestamp + minStakingTime);
        sortitionModule.passPhase();
        vm.warp(block.timestamp + rngLookahead);
        sortitionModule.passPhase();
    }

    function _staking() internal {
        vm.warp(block.timestamp + maxDrawingTime);
        sortitionModule.passPhase();
    }
}
