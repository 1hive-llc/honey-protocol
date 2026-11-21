// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {StakeWeight} from "../src/math/StakeWeight.sol";

contract StakeWeightTest is Test {
    function testSqrtBasicValues() public pure {
        assertEq(StakeWeight.sqrt(0), 0);
        assertEq(StakeWeight.sqrt(1), 1);
        assertEq(StakeWeight.sqrt(2), 1);
        assertEq(StakeWeight.sqrt(3), 1);
        assertEq(StakeWeight.sqrt(4), 2);
        assertEq(StakeWeight.sqrt(15), 3);
        assertEq(StakeWeight.sqrt(16), 4);
        assertEq(StakeWeight.sqrt(17), 4);
    }

    function testSqrtLargeValue() public pure {
        assertEq(StakeWeight.sqrt(10_000 ether), 100_000_000_000);
        assertEq(StakeWeight.sqrt(type(uint256).max), 340282366920938463463374607431768211455);
    }

    function testEffectiveWeightModes() public pure {
        assertEq(StakeWeight.effectiveWeight(10_000, StakeWeight.Mode.Linear), 10_000);
        assertEq(StakeWeight.effectiveWeight(10_000, StakeWeight.Mode.SquareRoot), 100);
    }

    function testSqrtFloorsFuzz(uint256 value) public pure {
        uint256 root = StakeWeight.sqrt(value);
        assertLe(root * root, value);
        if (root < type(uint128).max) {
            uint256 next = root + 1;
            assertGt(next * next, value);
        }
    }
}
