// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOptimisticArbitrator} from "./IOptimisticArbitrator.sol";
import {IERC20} from "../token/IERC20.sol";

interface IKlerosCoreForOptimisticAdapter {
    function arbitrationCost(bytes calldata extraData, IERC20 feeToken) external view returns (uint256);
    function createDispute(uint256 numberOfChoices, bytes calldata extraData, IERC20 feeToken, uint256 feeAmount)
        external
        returns (uint256 disputeID);
}

/// @notice Adapts Kleros v2's ERC20-fee arbitrator API to Honey's optimistic executor interface.
/// @dev Fund this adapter with the configured fee token before executor disputes are created. The adapter
/// relies on native Kleros court hierarchy for automation-to-human escalation and only releases an
/// automation-court ruling after `openRulingFinalityDelay`.
contract KlerosOptimisticArbitratorAdapter is IOptimisticArbitrator {
    error OwnerOnly();
    error CoreOnly();
    error FeeFundingTooLow(uint256 required, uint256 available);
    error ZeroAddress();
    error DisputeNotFound();
    error FeeApprovalFailed();

    struct DisputeLink {
        uint256 klerosDisputeId;
        bool openRuled;
        uint256 openRuling;
        uint64 openRuledAt;
    }

    event OwnerChanged(address indexed previousOwner, address indexed newOwner);
    event ExtraDataChanged(bytes automationCourtExtraData);
    event FeeTokenChanged(IERC20 indexed feeToken);
    event FinalityDelayChanged(uint64 openRulingFinalityDelay);
    event KlerosDisputeCreated(
        uint256 indexed localDisputeId, uint256 indexed klerosDisputeId, address indexed requester, bytes metadata
    );
    event KlerosRulingReceived(
        uint256 indexed localDisputeId, uint256 indexed klerosDisputeId, uint256 ruling, bool finalRuling
    );
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, bytes evidence);

    address public owner;
    IKlerosCoreForOptimisticAdapter public immutable klerosCore;
    IERC20 public feeToken;
    bytes public automationCourtExtraData;
    uint64 public openRulingFinalityDelay;
    uint256 public nextLocalDisputeId;

    mapping(uint256 localDisputeId => DisputeLink link) public disputes;
    mapping(uint256 klerosDisputeId => uint256 localDisputeId) public localDisputeByKlerosDispute;

    modifier onlyOwner() {
        if (msg.sender != owner) revert OwnerOnly();
        _;
    }

    constructor(
        IKlerosCoreForOptimisticAdapter klerosCore_,
        IERC20 feeToken_,
        bytes memory automationCourtExtraData_,
        uint64 openRulingFinalityDelay_,
        address owner_
    ) {
        if (address(klerosCore_) == address(0) || address(feeToken_) == address(0) || owner_ == address(0)) {
            revert ZeroAddress();
        }
        klerosCore = klerosCore_;
        feeToken = feeToken_;
        automationCourtExtraData = automationCourtExtraData_;
        openRulingFinalityDelay = openRulingFinalityDelay_;
        owner = owner_;
        emit OwnerChanged(address(0), owner_);
        emit FeeTokenChanged(feeToken_);
        emit ExtraDataChanged(automationCourtExtraData_);
        emit FinalityDelayChanged(openRulingFinalityDelay_);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function setFeeToken(IERC20 newFeeToken) external onlyOwner {
        if (address(newFeeToken) == address(0)) revert ZeroAddress();
        feeToken = newFeeToken;
        emit FeeTokenChanged(newFeeToken);
    }

    function setAutomationCourtExtraData(bytes calldata newExtraData) external onlyOwner {
        automationCourtExtraData = newExtraData;
        emit ExtraDataChanged(newExtraData);
    }

    function setOpenRulingFinalityDelay(uint64 finalityDelay) external onlyOwner {
        openRulingFinalityDelay = finalityDelay;
        emit FinalityDelayChanged(finalityDelay);
    }

    function withdrawFeeToken(address recipient, uint256 amount) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        feeToken.transfer(recipient, amount);
    }

    function arbitrationCost() public view returns (uint256) {
        return klerosCore.arbitrationCost(automationCourtExtraData, feeToken);
    }

    function createDispute(uint8 numberOfChoices, bytes calldata metadata) external returns (uint256 localDisputeId) {
        uint256 cost = arbitrationCost();
        uint256 balance = feeToken.balanceOf(address(this));
        if (balance < cost) revert FeeFundingTooLow(cost, balance);
        if (!feeToken.approve(address(klerosCore), cost)) revert FeeApprovalFailed();

        uint256 klerosDisputeId = klerosCore.createDispute(numberOfChoices, automationCourtExtraData, feeToken, cost);
        localDisputeId = nextLocalDisputeId++;
        disputes[localDisputeId].klerosDisputeId = klerosDisputeId;
        localDisputeByKlerosDispute[klerosDisputeId] = localDisputeId;

        emit KlerosDisputeCreated(localDisputeId, klerosDisputeId, msg.sender, metadata);
    }

    function submitEvidence(uint256 disputeId, address submitter, bytes calldata evidence) external {
        emit EvidenceSubmitted(disputeId, submitter, evidence);
    }

    function getRuling(uint256 localDisputeId) external view returns (bool isRuled, uint256 finalRuling) {
        if (localDisputeId >= nextLocalDisputeId) return (false, 0);
        DisputeLink storage link = disputes[localDisputeId];
        if (link.openRuled) {
            uint256 readyAt = uint256(link.openRuledAt) + openRulingFinalityDelay;
            if (block.timestamp >= readyAt) return (true, link.openRuling);
        }
        return (false, 0);
    }

    /// @notice KlerosCore callback invoked by `executeRuling`.
    function rule(uint256 klerosDisputeId, uint256 ruling) external {
        if (msg.sender != address(klerosCore)) revert CoreOnly();
        uint256 localDisputeId = localDisputeByKlerosDispute[klerosDisputeId];
        if (localDisputeId >= nextLocalDisputeId) revert DisputeNotFound();
        DisputeLink storage link = disputes[localDisputeId];
        link.openRuled = true;
        link.openRuling = ruling;
        link.openRuledAt = uint64(block.timestamp);
        emit KlerosRulingReceived(localDisputeId, klerosDisputeId, ruling, true);
    }
}
