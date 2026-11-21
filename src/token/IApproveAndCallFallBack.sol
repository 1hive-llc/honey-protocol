// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IApproveAndCallFallBack {
    function receiveApproval(address from, uint256 amount, address token, bytes calldata data) external;
}
