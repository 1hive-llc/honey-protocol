// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OptimisticExecutor} from "../optimistic/OptimisticExecutor.sol";

contract ReentrantExecutorTarget {
    OptimisticExecutor public immutable executor;
    uint256 public actionId;

    constructor(OptimisticExecutor executor_) {
        executor = executor_;
    }

    function setActionId(uint256 actionId_) external {
        actionId = actionId_;
    }

    function reenterExecute() external {
        executor.execute(actionId);
    }
}
