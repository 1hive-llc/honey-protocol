// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIdentityRegistry} from "../identity/IIdentityRegistry.sol";
import {IOptimisticArbitrator} from "../optimistic/IOptimisticArbitrator.sol";
import {IStakeRegistry} from "../staking/IStakeRegistry.sol";
import {StakeContext} from "../staking/StakeContext.sol";
import {HoneyCourtIds} from "./HoneyCourtIds.sol";
import {IStakeWeightStrategy} from "./IStakeWeightStrategy.sol";

/// @notice Local Honey v2 court integration scaffold.
/// @dev This is not the production Kleros fork. It models the Honey-specific
///      two-subcourt, stake-registry, eligibility, weighting, and escalation
///      semantics so they can be tested before porting into `vendor/kleros-v2`.
contract HoneyCourtMVP is IOptimisticArbitrator {
    enum DisputeStatus {
        None,
        Evidence,
        StakeRuled,
        Escalated,
        HumanRuled
    }

    struct Dispute {
        address subject;
        uint96 courtId;
        uint8 possibleRulings;
        bytes metadata;
        DisputeStatus status;
        uint256 stakeRuling;
        uint256 humanRuling;
        address escalator;
    }

    error NotOwner();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidCourt();
    error HumanCourtRequiresVerification();
    error InvalidDispute();
    error InvalidStatus();
    error InvalidRuling();

    address public owner;
    IStakeRegistry public immutable stakeRegistry;
    IIdentityRegistry public immutable identityRegistry;
    IStakeWeightStrategy public immutable weightStrategy;
    uint256 public immutable escalationBond;
    uint256 public nextDisputeId = 1;

    mapping(uint256 => Dispute) public disputes;
    mapping(address => mapping(uint96 => uint256)) public activeStake;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event StakeActivated(address indexed account, uint96 indexed courtId, uint256 amount);
    event StakeDeactivated(address indexed account, uint96 indexed courtId, uint256 amount);
    event DisputeCreated(
        uint256 indexed disputeId,
        uint96 indexed courtId,
        address indexed subject,
        uint8 possibleRulings,
        bytes metadata
    );
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, bytes evidence);
    event StakeCourtRuled(uint256 indexed disputeId, uint256 ruling);
    event EscalatedToHumanCourt(uint256 indexed disputeId, address indexed escalator);
    event HumanCourtRuled(uint256 indexed disputeId, uint256 ruling, bool escalationBondSlashed);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(
        IStakeRegistry stakeRegistry_,
        IIdentityRegistry identityRegistry_,
        IStakeWeightStrategy weightStrategy_,
        uint256 escalationBond_,
        address owner_
    ) {
        if (
            address(stakeRegistry_) == address(0) || address(identityRegistry_) == address(0)
                || address(weightStrategy_) == address(0)
        ) {
            revert ZeroAddress();
        }
        owner = owner_ == address(0) ? msg.sender : owner_;
        stakeRegistry = stakeRegistry_;
        identityRegistry = identityRegistry_;
        weightStrategy = weightStrategy_;
        escalationBond = escalationBond_;
        emit OwnershipTransferred(address(0), owner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function activateStake(uint96 courtId, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _checkCourt(courtId);
        if (courtId == HoneyCourtIds.HUMAN_COURT && !identityRegistry.isVerified(msg.sender)) {
            revert HumanCourtRequiresVerification();
        }

        activeStake[msg.sender][courtId] += amount;
        stakeRegistry.allocate(msg.sender, _stakeContext(courtId), _activeStakeLockId(msg.sender, courtId), amount);
        emit StakeActivated(msg.sender, courtId, amount);
    }

    function deactivateStake(uint96 courtId, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _checkCourt(courtId);
        if (activeStake[msg.sender][courtId] < amount) revert ZeroAmount();

        activeStake[msg.sender][courtId] -= amount;
        stakeRegistry.release(msg.sender, _stakeContext(courtId), _activeStakeLockId(msg.sender, courtId), amount);
        emit StakeDeactivated(msg.sender, courtId, amount);
    }

    function effectiveStake(address account, uint96 courtId) external view returns (uint256) {
        _checkCourt(courtId);
        return weightStrategy.effectiveStake(courtId, account, activeStake[account][courtId]);
    }

    function arbitrationCost() external pure returns (uint256) {
        return 0;
    }

    /// @notice IOptimisticArbitrator entrypoint. Defaults to the open stake court.
    function createDispute(uint8 possibleRulings, bytes calldata metadata) external returns (uint256 disputeId) {
        disputeId = _createDispute(HoneyCourtIds.STAKE_COURT, possibleRulings, metadata);
    }

    function createDisputeInCourt(uint96 courtId, uint8 possibleRulings, bytes calldata metadata)
        external
        returns (uint256 disputeId)
    {
        disputeId = _createDispute(courtId, possibleRulings, metadata);
    }

    function submitEvidence(uint256 disputeId, address submitter, bytes calldata evidence) external {
        Dispute storage dispute = disputes[disputeId];
        if (dispute.status == DisputeStatus.None) revert InvalidDispute();
        if (dispute.status == DisputeStatus.HumanRuled) revert InvalidStatus();
        emit EvidenceSubmitted(disputeId, submitter, evidence);
    }

    function ruleStakeCourt(uint256 disputeId, uint256 ruling) external onlyOwner {
        Dispute storage dispute = disputes[disputeId];
        if (dispute.status != DisputeStatus.Evidence) revert InvalidStatus();
        _checkRuling(dispute, ruling);
        dispute.status = DisputeStatus.StakeRuled;
        dispute.stakeRuling = ruling;
        emit StakeCourtRuled(disputeId, ruling);
    }

    function escalateToHumanCourt(uint256 disputeId) external {
        Dispute storage dispute = disputes[disputeId];
        if (dispute.status != DisputeStatus.StakeRuled) revert InvalidStatus();
        if (dispute.courtId != HoneyCourtIds.STAKE_COURT) revert InvalidCourt();

        dispute.status = DisputeStatus.Escalated;
        dispute.courtId = HoneyCourtIds.HUMAN_COURT;
        dispute.escalator = msg.sender;
        stakeRegistry.allocate(msg.sender, StakeContext.ESCALATION_BOND, _escalationLockId(disputeId), escalationBond);
        emit EscalatedToHumanCourt(disputeId, msg.sender);
    }

    function ruleHumanCourt(uint256 disputeId, uint256 ruling, bool slashEscalationBond, address slashRecipient)
        external
        onlyOwner
    {
        Dispute storage dispute = disputes[disputeId];
        if (dispute.status != DisputeStatus.Escalated) revert InvalidStatus();
        _checkRuling(dispute, ruling);

        dispute.status = DisputeStatus.HumanRuled;
        dispute.humanRuling = ruling;
        if (slashEscalationBond) {
            address recipient = slashRecipient == address(0) ? owner : slashRecipient;
            stakeRegistry.slash(
                dispute.escalator, StakeContext.ESCALATION_BOND, _escalationLockId(disputeId), recipient, escalationBond
            );
        } else {
            stakeRegistry.release(
                dispute.escalator, StakeContext.ESCALATION_BOND, _escalationLockId(disputeId), escalationBond
            );
        }
        emit HumanCourtRuled(disputeId, ruling, slashEscalationBond);
    }

    function getRuling(uint256 disputeId) external view returns (bool ruled, uint256 ruling) {
        Dispute storage dispute = disputes[disputeId];
        if (dispute.status == DisputeStatus.None) revert InvalidDispute();
        if (dispute.status == DisputeStatus.StakeRuled) return (true, dispute.stakeRuling);
        if (dispute.status == DisputeStatus.HumanRuled) return (true, dispute.humanRuling);
        return (false, 0);
    }

    function _createDispute(uint96 courtId, uint8 possibleRulings, bytes calldata metadata)
        internal
        returns (uint256 disputeId)
    {
        _checkCourt(courtId);
        if (possibleRulings < 2) revert InvalidRuling();
        disputeId = nextDisputeId++;
        disputes[disputeId] = Dispute({
            subject: msg.sender,
            courtId: courtId,
            possibleRulings: possibleRulings,
            metadata: metadata,
            status: DisputeStatus.Evidence,
            stakeRuling: 0,
            humanRuling: 0,
            escalator: address(0)
        });
        emit DisputeCreated(disputeId, courtId, msg.sender, possibleRulings, metadata);
    }

    function _checkCourt(uint96 courtId) internal pure {
        if (courtId != HoneyCourtIds.STAKE_COURT && courtId != HoneyCourtIds.HUMAN_COURT) revert InvalidCourt();
    }

    function _checkRuling(Dispute storage dispute, uint256 ruling) internal view {
        if (ruling == 0 || ruling > dispute.possibleRulings) revert InvalidRuling();
    }

    function _stakeContext(uint96 courtId) internal pure returns (bytes32) {
        return courtId == HoneyCourtIds.HUMAN_COURT ? StakeContext.HUMAN_COURT_ACTIVE : StakeContext.STAKE_COURT_ACTIVE;
    }

    function _activeStakeLockId(address account, uint96 courtId) internal pure returns (bytes32) {
        return keccak256(abi.encode("COURT_ACTIVE", account, courtId));
    }

    function _escalationLockId(uint256 disputeId) internal pure returns (bytes32) {
        return keccak256(abi.encode("ESCALATION", disputeId));
    }
}
