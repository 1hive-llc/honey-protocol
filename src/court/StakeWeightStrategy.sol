// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {HoneyCourtIds} from "./HoneyCourtIds.sol";
import {IStakeWeightStrategy} from "./IStakeWeightStrategy.sol";
import {StakeWeight} from "../math/StakeWeight.sol";

/// @notice Initial Honey v2 effective stake strategy for Kleros fork integration.
contract StakeWeightStrategy is IStakeWeightStrategy {
    function effectiveStake(uint96 courtId, address, uint256 rawActiveStake) external pure returns (uint256) {
        if (courtId == HoneyCourtIds.HUMAN_COURT || courtId == HoneyCourtIds.STAKE_COURT) {
            return StakeWeight.effectiveWeight(rawActiveStake, StakeWeight.Mode.SquareRoot);
        }
        return StakeWeight.effectiveWeight(rawActiveStake, StakeWeight.Mode.Linear);
    }
}
