// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIdentityRegistry} from "./IIdentityRegistry.sol";
import {IStakeRegistry} from "../staking/IStakeRegistry.sol";
import {StakeContext} from "../staking/StakeContext.sol";
import {IOptimisticArbitrator} from "../optimistic/IOptimisticArbitrator.sol";

/// @notice MVP optimistic identity registry backed by generic ERC20 stake bonds and court rulings.
/// @dev This contract is an implementation scaffold for the Honey v2 roadmap. It keeps on-chain
///      identity data minimal: accounts, statuses, opaque evidence hashes, bonds, and dispute ids.
contract OptimisticIdentityRegistry is IIdentityRegistry {
    enum ApplicationStatus {
        None,
        Pending,
        Challenged,
        Verified,
        Rejected
    }

    enum MemberChallengeStatus {
        None,
        PendingResponse,
        Disputed,
        MemberWon,
        ChallengerWon
    }

    struct Application {
        address account;
        address applicant;
        bytes32 evidenceHash;
        uint64 submittedAt;
        uint64 challengeDeadline;
        ApplicationStatus status;
        address challenger;
        address defender;
        uint64 responseDeadline;
        bytes32 challengeEvidenceHash;
        bytes32 responseEvidenceHash;
        uint256 disputeId;
    }

    struct MemberChallenge {
        address member;
        address challenger;
        address defender;
        bytes32 evidenceHash;
        bytes32 responseEvidenceHash;
        uint64 challengedAt;
        uint64 responseDeadline;
        MemberChallengeStatus status;
        uint256 disputeId;
    }

    error ZeroAddress();
    error ZeroDuration();
    error AlreadyVerified();
    error AlreadyApplied();
    error ApplicationNotPending();
    error ChallengeWindowOpen();
    error ChallengeWindowClosed();
    error InvalidStatus();
    error ResponseWindowClosed();
    error ResponseWindowOpen();
    error NotVerified();
    error NotRuled();
    error InvalidRuling();
    error ExitWindowOpen();
    error ActiveChallenge();

    IStakeRegistry public immutable stakeRegistry;
    IOptimisticArbitrator public immutable arbitrator;

    uint256 public immutable applicationBond;
    uint256 public immutable challengeBond;
    uint256 public immutable responseBond;
    uint64 public immutable challengeDuration;
    uint64 public immutable responseDuration;
    uint64 public immutable exitDelay;

    uint256 public applicationCount;
    uint256 public memberChallengeCount;

    mapping(address => IdentityStatus) private _status;
    mapping(address => uint256) public latestApplicationOf;
    mapping(address => uint256) public activeMemberChallengeOf;
    mapping(address => uint64) public exitAvailableAt;
    mapping(uint256 => Application) public applications;
    mapping(uint256 => MemberChallenge) public memberChallenges;

    event ApplicationSubmitted(
        uint256 indexed applicationId,
        address indexed account,
        address indexed applicant,
        bytes32 evidenceHash,
        uint64 challengeDeadline
    );
    event ApplicationChallenged(
        uint256 indexed applicationId, address indexed challenger, uint256 disputeId, bytes32 evidenceHash
    );
    event ApplicationDefended(uint256 indexed applicationId, address indexed defender, bytes32 evidenceHash);
    event ApplicationFinalized(uint256 indexed applicationId, address indexed account);
    event ApplicationRejected(uint256 indexed applicationId, address indexed account);
    event MemberChallengeSubmitted(
        uint256 indexed challengeId, address indexed member, address indexed challenger, bytes32 evidenceHash
    );
    event MemberChallengeDefended(
        uint256 indexed challengeId, address indexed defender, uint256 disputeId, bytes32 evidenceHash
    );
    event MemberChallengeResolved(uint256 indexed challengeId, address indexed member, uint256 ruling);
    event ExitRequested(address indexed account, uint64 availableAt);
    event ExitFinalized(address indexed account);

    constructor(
        IStakeRegistry stakeRegistry_,
        IOptimisticArbitrator arbitrator_,
        uint256 applicationBond_,
        uint256 challengeBond_,
        uint256 responseBond_,
        uint64 challengeDuration_,
        uint64 responseDuration_,
        uint64 exitDelay_
    ) {
        if (address(stakeRegistry_) == address(0) || address(arbitrator_) == address(0)) {
            revert ZeroAddress();
        }
        if (challengeDuration_ == 0 || responseDuration_ == 0 || exitDelay_ == 0) revert ZeroDuration();
        stakeRegistry = stakeRegistry_;
        arbitrator = arbitrator_;
        applicationBond = applicationBond_;
        challengeBond = challengeBond_;
        responseBond = responseBond_;
        challengeDuration = challengeDuration_;
        responseDuration = responseDuration_;
        exitDelay = exitDelay_;
    }

    function applyForVerification(bytes32 evidenceHash) external returns (uint256 applicationId) {
        address account = msg.sender;
        if (_status[account] == IdentityStatus.Verified) revert AlreadyVerified();
        uint256 latest = latestApplicationOf[account];
        if (latest != 0) {
            ApplicationStatus latestStatus = applications[latest].status;
            if (latestStatus == ApplicationStatus.Pending || latestStatus == ApplicationStatus.Challenged) {
                revert AlreadyApplied();
            }
        }

        applicationId = ++applicationCount;
        uint64 deadline = uint64(block.timestamp) + challengeDuration;
        applications[applicationId] = Application({
            account: account,
            applicant: msg.sender,
            evidenceHash: evidenceHash,
            submittedAt: uint64(block.timestamp),
            challengeDeadline: deadline,
            status: ApplicationStatus.Pending,
            challenger: address(0),
            defender: address(0),
            responseDeadline: 0,
            challengeEvidenceHash: bytes32(0),
            responseEvidenceHash: bytes32(0),
            disputeId: 0
        });
        latestApplicationOf[account] = applicationId;
        stakeRegistry.allocate(account, StakeContext.IDENTITY_BOND, _applicationLockId(applicationId), applicationBond);
        emit ApplicationSubmitted(applicationId, account, msg.sender, evidenceHash, deadline);
    }

    function finalizeApplication(uint256 applicationId) external {
        Application storage application = applications[applicationId];
        if (application.status != ApplicationStatus.Pending) revert ApplicationNotPending();
        if (block.timestamp < application.challengeDeadline) revert ChallengeWindowOpen();
        application.status = ApplicationStatus.Verified;
        _status[application.account] = IdentityStatus.Verified;
        emit ApplicationFinalized(applicationId, application.account);
    }

    function challengeApplication(uint256 applicationId, bytes32 evidenceHash) external returns (uint256 disputeId) {
        Application storage application = applications[applicationId];
        if (application.status != ApplicationStatus.Pending) revert ApplicationNotPending();
        if (block.timestamp >= application.challengeDeadline) revert ChallengeWindowClosed();

        application.status = ApplicationStatus.Challenged;
        application.challenger = msg.sender;
        application.responseDeadline = uint64(block.timestamp) + responseDuration;
        application.challengeEvidenceHash = evidenceHash;
        disputeId = arbitrator.createDispute(
            2, abi.encode("REGISTRY_APPLICATION", applicationId, application.account, evidenceHash)
        );
        application.disputeId = disputeId;

        stakeRegistry.allocate(
            msg.sender, StakeContext.REGISTRY_CHALLENGE_BOND, _applicationChallengeLockId(applicationId), challengeBond
        );
        emit ApplicationChallenged(applicationId, msg.sender, disputeId, evidenceHash);
    }

    function defendApplication(uint256 applicationId, bytes32 evidenceHash) external {
        Application storage application = applications[applicationId];
        if (application.status != ApplicationStatus.Challenged) revert InvalidStatus();
        if (block.timestamp >= application.responseDeadline) revert ResponseWindowClosed();
        if (application.defender != address(0)) revert InvalidStatus();

        application.defender = msg.sender;
        application.responseEvidenceHash = evidenceHash;
        stakeRegistry.allocate(
            msg.sender, StakeContext.REGISTRY_RESPONSE_BOND, _applicationResponseLockId(applicationId), responseBond
        );
        emit ApplicationDefended(applicationId, msg.sender, evidenceHash);
    }

    function claimApplicationDefault(uint256 applicationId) external {
        Application storage application = applications[applicationId];
        if (application.status != ApplicationStatus.Challenged) revert InvalidStatus();
        if (application.defender != address(0)) revert InvalidStatus();
        if (block.timestamp < application.responseDeadline) revert ResponseWindowOpen();
        _rejectApplication(applicationId, application);
    }

    function resolveApplication(uint256 applicationId) external {
        Application storage application = applications[applicationId];
        if (application.status != ApplicationStatus.Challenged) revert InvalidStatus();
        if (application.defender == address(0)) revert InvalidStatus();

        (bool ruled, uint256 ruling) = arbitrator.getRuling(application.disputeId);
        if (!ruled) revert NotRuled();
        if (ruling == 1) {
            application.status = ApplicationStatus.Verified;
            _status[application.account] = IdentityStatus.Verified;
            stakeRegistry.release(
                application.defender,
                StakeContext.REGISTRY_RESPONSE_BOND,
                _applicationResponseLockId(applicationId),
                responseBond
            );
            stakeRegistry.slash(
                application.challenger,
                StakeContext.REGISTRY_CHALLENGE_BOND,
                _applicationChallengeLockId(applicationId),
                application.defender,
                challengeBond
            );
            emit ApplicationFinalized(applicationId, application.account);
        } else if (ruling == 2) {
            _rejectApplication(applicationId, application);
            if (application.defender != address(0)) {
                stakeRegistry.slash(
                    application.defender,
                    StakeContext.REGISTRY_RESPONSE_BOND,
                    _applicationResponseLockId(applicationId),
                    application.challenger,
                    responseBond
                );
            }
        } else {
            revert InvalidRuling();
        }
    }

    function challengeMember(address member, bytes32 evidenceHash) external returns (uint256 challengeId) {
        if (_status[member] != IdentityStatus.Verified) revert NotVerified();
        if (activeMemberChallengeOf[member] != 0) revert ActiveChallenge();

        challengeId = ++memberChallengeCount;
        uint64 responseDeadline = uint64(block.timestamp) + responseDuration;
        memberChallenges[challengeId] = MemberChallenge({
            member: member,
            challenger: msg.sender,
            defender: address(0),
            evidenceHash: evidenceHash,
            responseEvidenceHash: bytes32(0),
            challengedAt: uint64(block.timestamp),
            responseDeadline: responseDeadline,
            status: MemberChallengeStatus.PendingResponse,
            disputeId: 0
        });
        activeMemberChallengeOf[member] = challengeId;
        stakeRegistry.allocate(
            msg.sender, StakeContext.REGISTRY_CHALLENGE_BOND, _memberChallengeLockId(challengeId), challengeBond
        );
        emit MemberChallengeSubmitted(challengeId, member, msg.sender, evidenceHash);
    }

    function defendMember(uint256 challengeId, bytes32 evidenceHash) external returns (uint256 disputeId) {
        MemberChallenge storage memberChallenge = memberChallenges[challengeId];
        if (memberChallenge.status != MemberChallengeStatus.PendingResponse) revert InvalidStatus();
        if (block.timestamp >= memberChallenge.responseDeadline) revert ResponseWindowClosed();

        memberChallenge.status = MemberChallengeStatus.Disputed;
        memberChallenge.defender = msg.sender;
        memberChallenge.responseEvidenceHash = evidenceHash;
        disputeId = arbitrator.createDispute(
            2, abi.encode("REGISTRY_MEMBER", challengeId, memberChallenge.member, evidenceHash)
        );
        memberChallenge.disputeId = disputeId;

        stakeRegistry.allocate(
            msg.sender, StakeContext.REGISTRY_RESPONSE_BOND, _memberResponseLockId(challengeId), responseBond
        );
        emit MemberChallengeDefended(challengeId, msg.sender, disputeId, evidenceHash);
    }

    function claimMemberChallengeDefault(uint256 challengeId) external {
        MemberChallenge storage memberChallenge = memberChallenges[challengeId];
        if (memberChallenge.status != MemberChallengeStatus.PendingResponse) revert InvalidStatus();
        if (block.timestamp < memberChallenge.responseDeadline) revert ResponseWindowOpen();
        _memberChallengerWins(challengeId, memberChallenge);
    }

    function resolveMemberChallenge(uint256 challengeId) external {
        MemberChallenge storage memberChallenge = memberChallenges[challengeId];
        if (memberChallenge.status != MemberChallengeStatus.Disputed) revert InvalidStatus();
        (bool ruled, uint256 ruling) = arbitrator.getRuling(memberChallenge.disputeId);
        if (!ruled) revert NotRuled();
        if (ruling == 1) {
            memberChallenge.status = MemberChallengeStatus.MemberWon;
            activeMemberChallengeOf[memberChallenge.member] = 0;
            stakeRegistry.release(
                memberChallenge.defender,
                StakeContext.REGISTRY_RESPONSE_BOND,
                _memberResponseLockId(challengeId),
                responseBond
            );
            stakeRegistry.slash(
                memberChallenge.challenger,
                StakeContext.REGISTRY_CHALLENGE_BOND,
                _memberChallengeLockId(challengeId),
                memberChallenge.defender,
                challengeBond
            );
            emit MemberChallengeResolved(challengeId, memberChallenge.member, ruling);
        } else if (ruling == 2) {
            _memberChallengerWins(challengeId, memberChallenge);
            stakeRegistry.slash(
                memberChallenge.defender,
                StakeContext.REGISTRY_RESPONSE_BOND,
                _memberResponseLockId(challengeId),
                memberChallenge.challenger,
                responseBond
            );
        } else {
            revert InvalidRuling();
        }
    }

    function requestExit() external {
        if (_status[msg.sender] != IdentityStatus.Verified) revert NotVerified();
        if (activeMemberChallengeOf[msg.sender] != 0) revert ActiveChallenge();
        uint64 availableAt = uint64(block.timestamp) + exitDelay;
        exitAvailableAt[msg.sender] = availableAt;
        emit ExitRequested(msg.sender, availableAt);
    }

    function finalizeExit() external {
        if (_status[msg.sender] != IdentityStatus.Verified) revert NotVerified();
        if (activeMemberChallengeOf[msg.sender] != 0) revert ActiveChallenge();
        uint64 availableAt = exitAvailableAt[msg.sender];
        if (availableAt == 0) revert InvalidStatus();
        if (block.timestamp < availableAt) revert ExitWindowOpen();

        _status[msg.sender] = IdentityStatus.Revoked;
        exitAvailableAt[msg.sender] = 0;
        uint256 applicationId = latestApplicationOf[msg.sender];
        stakeRegistry.release(
            msg.sender, StakeContext.IDENTITY_BOND, _applicationLockId(applicationId), applicationBond
        );
        emit ExitFinalized(msg.sender);
    }

    function isVerified(address account) external view returns (bool) {
        return _status[account] == IdentityStatus.Verified;
    }

    function hasUniqueUserId(address account) external view returns (bool) {
        return _status[account] == IdentityStatus.Verified;
    }

    function uniqueUserId(address account) external pure returns (address) {
        return account;
    }

    function statusOf(address identity) external view returns (IdentityStatus) {
        return _status[identity];
    }

    function _rejectApplication(uint256 applicationId, Application storage application) internal {
        application.status = ApplicationStatus.Rejected;
        _status[application.account] = IdentityStatus.Revoked;
        stakeRegistry.slash(
            application.account,
            StakeContext.IDENTITY_BOND,
            _applicationLockId(applicationId),
            application.challenger,
            applicationBond
        );
        stakeRegistry.release(
            application.challenger,
            StakeContext.REGISTRY_CHALLENGE_BOND,
            _applicationChallengeLockId(applicationId),
            challengeBond
        );
        emit ApplicationRejected(applicationId, application.account);
    }

    function _memberChallengerWins(uint256 challengeId, MemberChallenge storage memberChallenge) internal {
        memberChallenge.status = MemberChallengeStatus.ChallengerWon;
        activeMemberChallengeOf[memberChallenge.member] = 0;
        _status[memberChallenge.member] = IdentityStatus.Revoked;
        uint256 applicationId = latestApplicationOf[memberChallenge.member];
        stakeRegistry.slash(
            memberChallenge.member,
            StakeContext.IDENTITY_BOND,
            _applicationLockId(applicationId),
            memberChallenge.challenger,
            applicationBond
        );
        stakeRegistry.release(
            memberChallenge.challenger,
            StakeContext.REGISTRY_CHALLENGE_BOND,
            _memberChallengeLockId(challengeId),
            challengeBond
        );
        emit MemberChallengeResolved(challengeId, memberChallenge.member, 2);
    }

    function _applicationLockId(uint256 applicationId) internal pure returns (bytes32) {
        return keccak256(abi.encode("IDENTITY_APPLICATION", applicationId));
    }

    function _applicationChallengeLockId(uint256 applicationId) internal pure returns (bytes32) {
        return keccak256(abi.encode("IDENTITY_APPLICATION_CHALLENGE", applicationId));
    }

    function _applicationResponseLockId(uint256 applicationId) internal pure returns (bytes32) {
        return keccak256(abi.encode("IDENTITY_APPLICATION_RESPONSE", applicationId));
    }

    function _memberChallengeLockId(uint256 challengeId) internal pure returns (bytes32) {
        return keccak256(abi.encode("IDENTITY_MEMBER_CHALLENGE", challengeId));
    }

    function _memberResponseLockId(uint256 challengeId) internal pure returns (bytes32) {
        return keccak256(abi.encode("IDENTITY_MEMBER_RESPONSE", challengeId));
    }
}
