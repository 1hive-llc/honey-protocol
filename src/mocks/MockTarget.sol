// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockTarget {
    uint256 public value;
    address public lastCaller;
    uint256 public received;
    bool public shouldRevert;

    event ValueSet(uint256 value, address caller, uint256 received);

    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function setValue(uint256 value_) external payable {
        if (shouldRevert) revert("MOCK_REVERT");
        value = value_;
        lastCaller = msg.sender;
        received += msg.value;
        emit ValueSet(value_, msg.sender, msg.value);
    }
}
