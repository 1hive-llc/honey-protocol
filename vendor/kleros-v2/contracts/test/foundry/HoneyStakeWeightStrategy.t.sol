// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {HoneyStakeWeightStrategy} from "../../src/honey/HoneyStakeWeightStrategy.sol";

contract HoneyStakeWeightStrategyTest is Test {
    function stakeIdentity(address account) external pure returns (address) { return account; }
    uint96 internal constant HUMAN_COURT = 1;
    uint96 internal constant AUTOMATION_COURT = 2;
    uint96 internal constant OTHER_COURT = 99;

    function testGeneralCourtUsesLinearWeight() public {
        HoneyStakeWeightStrategy strategy = new HoneyStakeWeightStrategy(HUMAN_COURT, AUTOMATION_COURT, address(this));
        assertEq(strategy.effectiveStake(OTHER_COURT, address(0xBEEF), 10_000), 10_000);
    }

    function testHumanAndAutomationCourtsUseSquareRootWeight() public {
        HoneyStakeWeightStrategy strategy = new HoneyStakeWeightStrategy(HUMAN_COURT, AUTOMATION_COURT, address(this));
        assertEq(strategy.effectiveStake(HUMAN_COURT, address(0xBEEF), 10_000), 100);
        assertEq(strategy.effectiveStake(AUTOMATION_COURT, address(0xBEEF), 10_000), 100);
        assertEq(strategy.effectiveStake(HUMAN_COURT, address(0xBEEF), 10_201), 101);
        assertEq(strategy.effectiveStake(AUTOMATION_COURT, address(0xBEEF), 10_201), 101);
    }

    function testSquareRootFuzz(uint256 rawStake) public {
        HoneyStakeWeightStrategy strategy = new HoneyStakeWeightStrategy(HUMAN_COURT, AUTOMATION_COURT, address(this));
        uint256 root = strategy.effectiveStake(AUTOMATION_COURT, address(0xBEEF), rawStake);
        assertLe(root * root, rawStake);
        if (root < type(uint128).max) {
            uint256 next = root + 1;
            assertGt(next * next, rawStake);
        }
    }
}
