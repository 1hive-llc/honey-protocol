// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOptimisticArbitrator} from "../optimistic/IOptimisticArbitrator.sol";
import {IStakeRegistry} from "../staking/IStakeRegistry.sol";
import {StakeContext} from "../staking/StakeContext.sol";

/// @notice Production-path manager for 1Hive content challenge side-pool funding.
/// @dev Uses deposited StakeRegistry HNY. The manager must be authorized as a StakeRegistry manager.
contract ContentChallengeManager {
    enum Status {
        None,
        ResponseFunding,
        Disputed,
        Defaulted,
        Settled
    }

    enum Side {
        None,
        Remove,
        Restore
    }

    uint256 public constant RULING_REMOVE = 1;
    uint256 public constant RULING_RESTORE = 2;

    struct Contribution {
        uint256 amount;
        uint256 feeSpent;
        bool exists;
    }

    struct Challenge {
        bytes32 contentId;
        bytes32 localCaseIdHash;
        address challenger;
        address respondent;
        uint64 responseDeadline;
        Status status;
        uint256 removeFunded;
        uint256 restoreFunded;
        uint256 localDisputeId;
        uint256 ruling;
    }

    error ZeroAddress();
    error ZeroAmount();
    error InvalidTarget();
    error InvalidStatus();
    error ResponseWindowOpen();
    error ResponseWindowClosed();
    error RestoreNotFunded();
    error DisputeNotRuled();
    error UnknownChallenge();
    error NotIntentExecutor();

    IStakeRegistry public immutable stakeRegistry;
    IOptimisticArbitrator public arbitrator;
    address public owner;
    address public treasury;
    uint256 public sideFundingTarget;
    uint64 public responseDuration;
    uint256 public nextChallengeId = 1;

    mapping(address executor => bool enabled) public intentExecutors;
    mapping(uint256 challengeId => Challenge challenge) public challenges;
    mapping(uint256 challengeId => mapping(Side side => address[] contributors)) private _contributors;
    mapping(uint256 challengeId => mapping(Side side => mapping(address contributor => Contribution contribution)))
        public contributions;
    mapping(uint256 localDisputeId => uint256 challengeId) public challengeByLocalDispute;

    event OwnerChanged(address indexed previousOwner, address indexed newOwner);
    event ConfigChanged(
        address indexed arbitrator, address indexed treasury, uint256 sideFundingTarget, uint64 responseDuration
    );
    event IntentExecutorSet(address indexed executor, bool enabled);
    event ContentChallengeOpened(
        uint256 indexed challengeId,
        bytes32 indexed contentId,
        bytes32 indexed localCaseIdHash,
        address challenger,
        address respondent,
        uint256 amount,
        uint64 responseDeadline,
        string evidenceURI
    );
    event RestoreFunded(
        uint256 indexed challengeId, address indexed contributor, uint256 amount, uint256 total, string evidenceURI
    );
    event ContentChallengeDisputed(
        uint256 indexed challengeId, uint256 indexed localDisputeId, uint256 arbitrationCost, string evidenceURI
    );
    event ContentChallengeDefaulted(uint256 indexed challengeId);
    event ContentChallengeSettled(uint256 indexed challengeId, uint256 ruling);

    modifier onlyOwner() {
        if (msg.sender != owner) revert InvalidStatus();
        _;
    }

    modifier onlyIntentExecutor() {
        if (!intentExecutors[msg.sender]) revert NotIntentExecutor();
        _;
    }

    constructor(
        IStakeRegistry stakeRegistry_,
        IOptimisticArbitrator arbitrator_,
        address treasury_,
        uint256 sideFundingTarget_,
        uint64 responseDuration_,
        address owner_
    ) {
        if (address(stakeRegistry_) == address(0) || address(arbitrator_) == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }
        if (sideFundingTarget_ == 0 || responseDuration_ == 0) revert ZeroAmount();
        stakeRegistry = stakeRegistry_;
        arbitrator = arbitrator_;
        treasury = treasury_;
        sideFundingTarget = sideFundingTarget_;
        responseDuration = responseDuration_;
        owner = owner_ == address(0) ? msg.sender : owner_;
        emit OwnerChanged(address(0), owner);
        emit ConfigChanged(address(arbitrator_), treasury_, sideFundingTarget_, responseDuration_);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function setConfig(
        IOptimisticArbitrator arbitrator_,
        address treasury_,
        uint256 sideFundingTarget_,
        uint64 responseDuration_
    ) external onlyOwner {
        if (address(arbitrator_) == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }
        if (sideFundingTarget_ == 0 || responseDuration_ == 0) revert ZeroAmount();
        arbitrator = arbitrator_;
        treasury = treasury_;
        sideFundingTarget = sideFundingTarget_;
        responseDuration = responseDuration_;
        emit ConfigChanged(address(arbitrator_), treasury_, sideFundingTarget_, responseDuration_);
    }

    function setIntentExecutor(address executor, bool enabled) external onlyOwner {
        if (executor == address(0)) revert ZeroAddress();
        intentExecutors[executor] = enabled;
        emit IntentExecutorSet(executor, enabled);
    }

    function openChallenge(bytes32 contentId, bytes32 localCaseIdHash, address respondent, string calldata evidenceURI)
        external
        returns (uint256 challengeId)
    {
        return _openChallenge(msg.sender, contentId, localCaseIdHash, respondent, evidenceURI);
    }

    function openChallengeFor(
        address challenger,
        bytes32 contentId,
        bytes32 localCaseIdHash,
        address respondent,
        string calldata evidenceURI
    ) external onlyIntentExecutor returns (uint256 challengeId) {
        return _openChallenge(challenger, contentId, localCaseIdHash, respondent, evidenceURI);
    }

    function fundRestore(uint256 challengeId, uint256 amount, string calldata evidenceURI) external {
        _fundRestore(challengeId, msg.sender, amount, evidenceURI);
    }

    function fundRestoreFor(uint256 challengeId, address contributor, uint256 amount, string calldata evidenceURI)
        external
        onlyIntentExecutor
    {
        _fundRestore(challengeId, contributor, amount, evidenceURI);
    }

    function createDispute(uint256 challengeId, string calldata evidenceURI) external returns (uint256 localDisputeId) {
        Challenge storage c = _challenge(challengeId);
        if (c.status != Status.ResponseFunding) revert InvalidStatus();
        if (block.timestamp > c.responseDeadline) revert ResponseWindowClosed();
        if (c.restoreFunded < sideFundingTarget) revert RestoreNotFunded();

        uint256 cost = arbitrator.arbitrationCost();
        if (cost > 0) {
            _spendFee(challengeId, Side.Remove, cost / 2, address(arbitrator));
            _spendFee(challengeId, Side.Restore, cost - (cost / 2), address(arbitrator));
        }
        localDisputeId = arbitrator.createDispute(2, bytes(evidenceURI));
        c.status = Status.Disputed;
        c.localDisputeId = localDisputeId;
        challengeByLocalDispute[localDisputeId] = challengeId;
        emit ContentChallengeDisputed(challengeId, localDisputeId, cost, evidenceURI);
    }

    function executeDefault(uint256 challengeId) external {
        Challenge storage c = _challenge(challengeId);
        if (c.status != Status.ResponseFunding) revert InvalidStatus();
        if (block.timestamp <= c.responseDeadline) revert ResponseWindowOpen();
        if (c.restoreFunded >= sideFundingTarget) revert InvalidStatus();
        c.status = Status.Defaulted;
        c.ruling = RULING_REMOVE;
        _releaseSide(challengeId, Side.Remove);
        emit ContentChallengeDefaulted(challengeId);
    }

    function executeRuling(uint256 challengeId) external {
        Challenge storage c = _challenge(challengeId);
        if (c.status != Status.Disputed) revert InvalidStatus();
        (bool ruled, uint256 ruling) = arbitrator.getRuling(c.localDisputeId);
        if (!ruled) revert DisputeNotRuled();
        c.ruling = ruling;
        c.status = Status.Settled;
        if (ruling == RULING_REMOVE) {
            _settleWinnerLoser(challengeId, Side.Remove, Side.Restore);
        } else if (ruling == RULING_RESTORE) {
            _settleWinnerLoser(challengeId, Side.Restore, Side.Remove);
        } else {
            _releaseSide(challengeId, Side.Remove);
            _releaseSide(challengeId, Side.Restore);
        }
        emit ContentChallengeSettled(challengeId, ruling);
    }

    function contributors(uint256 challengeId, Side side) external view returns (address[] memory) {
        return _contributors[challengeId][side];
    }

    function lockId(uint256 challengeId, Side side, address contributor) public pure returns (bytes32) {
        return keccak256(abi.encode("CONTENT_CHALLENGE", challengeId, side, contributor));
    }

    function remainingContribution(uint256 challengeId, Side side, address contributor) public view returns (uint256) {
        Contribution storage contribution = contributions[challengeId][side][contributor];
        return contribution.amount - contribution.feeSpent;
    }

    function _challenge(uint256 challengeId) internal view returns (Challenge storage c) {
        c = challenges[challengeId];
        if (c.status == Status.None) revert UnknownChallenge();
    }

    function _openChallenge(
        address challenger,
        bytes32 contentId,
        bytes32 localCaseIdHash,
        address respondent,
        string calldata evidenceURI
    ) internal returns (uint256 challengeId) {
        if (contentId == bytes32(0) || challenger == address(0) || respondent == address(0) || respondent == challenger)
        {
            revert InvalidTarget();
        }
        challengeId = nextChallengeId++;
        uint64 deadline = uint64(block.timestamp) + responseDuration;
        Challenge storage c = challenges[challengeId];
        c.contentId = contentId;
        c.localCaseIdHash = localCaseIdHash;
        c.challenger = challenger;
        c.respondent = respondent;
        c.responseDeadline = deadline;
        c.status = Status.ResponseFunding;
        c.removeFunded = sideFundingTarget;

        _addContribution(challengeId, Side.Remove, challenger, sideFundingTarget);
        stakeRegistry.allocate(
            challenger, StakeContext.CONTENT_CHALLENGE, lockId(challengeId, Side.Remove, challenger), sideFundingTarget
        );

        emit ContentChallengeOpened(
            challengeId, contentId, localCaseIdHash, challenger, respondent, sideFundingTarget, deadline, evidenceURI
        );
    }

    function _fundRestore(uint256 challengeId, address contributor, uint256 amount, string calldata evidenceURI)
        internal
    {
        if (contributor == address(0)) revert ZeroAddress();
        Challenge storage c = _challenge(challengeId);
        if (c.status != Status.ResponseFunding) revert InvalidStatus();
        if (block.timestamp > c.responseDeadline) revert ResponseWindowClosed();
        if (amount == 0) revert ZeroAmount();
        uint256 remaining = sideFundingTarget - c.restoreFunded;
        if (amount > remaining) amount = remaining;
        c.restoreFunded += amount;
        _addContribution(challengeId, Side.Restore, contributor, amount);
        stakeRegistry.allocate(
            contributor, StakeContext.CONTENT_CHALLENGE, lockId(challengeId, Side.Restore, contributor), amount
        );
        emit RestoreFunded(challengeId, contributor, amount, c.restoreFunded, evidenceURI);
    }

    function _addContribution(uint256 challengeId, Side side, address contributor, uint256 amount) internal {
        Contribution storage contribution = contributions[challengeId][side][contributor];
        if (!contribution.exists) {
            contribution.exists = true;
            _contributors[challengeId][side].push(contributor);
        }
        contribution.amount += amount;
    }

    function _spendFee(uint256 challengeId, Side side, uint256 fee, address recipient) internal {
        if (fee == 0) return;
        address[] storage accounts = _contributors[challengeId][side];
        uint256 sideTotal =
            side == Side.Remove ? challenges[challengeId].removeFunded : challenges[challengeId].restoreFunded;
        uint256 spent;
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            uint256 share = i == accounts.length - 1
                ? fee - spent
                : (fee * contributions[challengeId][side][account].amount) / sideTotal;
            if (share == 0) continue;
            spent += share;
            contributions[challengeId][side][account].feeSpent += share;
            stakeRegistry.spendLocked(
                account, StakeContext.CONTENT_CHALLENGE, lockId(challengeId, side, account), recipient, share
            );
        }
    }

    function _releaseSide(uint256 challengeId, Side side) internal {
        address[] storage accounts = _contributors[challengeId][side];
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            uint256 amount = remainingContribution(challengeId, side, account);
            if (amount > 0) {
                stakeRegistry.release(
                    account, StakeContext.CONTENT_CHALLENGE, lockId(challengeId, side, account), amount
                );
            }
        }
    }

    function _settleWinnerLoser(uint256 challengeId, Side winner, Side loser) internal {
        _releaseSide(challengeId, winner);
        uint256 winnerTotal = _remainingSideTotal(challengeId, winner);
        uint256 loserTotal = _remainingSideTotal(challengeId, loser);
        if (winnerTotal == 0 || loserTotal == 0) {
            _releaseSide(challengeId, loser);
            return;
        }
        address[] storage winners = _contributors[challengeId][winner];
        address[] storage losers = _contributors[challengeId][loser];
        uint256 distributed;
        for (uint256 wi = 0; wi < winners.length; wi++) {
            address winnerAccount = winners[wi];
            uint256 reward = wi == winners.length - 1
                ? loserTotal - distributed
                : (loserTotal * remainingContribution(challengeId, winner, winnerAccount)) / winnerTotal;
            distributed += reward;
            _slashLoserPoolToRecipient(challengeId, loser, losers, winnerAccount, reward);
        }
    }

    function _slashLoserPoolToRecipient(
        uint256 challengeId,
        Side loser,
        address[] storage losers,
        address recipient,
        uint256 amount
    ) internal {
        uint256 remaining = amount;
        for (uint256 li = 0; li < losers.length && remaining > 0; li++) {
            address loserAccount = losers[li];
            uint256 available = remainingContribution(challengeId, loser, loserAccount);
            if (available == 0) continue;
            uint256 slashAmount = available < remaining ? available : remaining;
            contributions[challengeId][loser][loserAccount].feeSpent += slashAmount;
            remaining -= slashAmount;
            stakeRegistry.slash(
                loserAccount,
                StakeContext.CONTENT_CHALLENGE,
                lockId(challengeId, loser, loserAccount),
                recipient,
                slashAmount
            );
        }
        if (remaining > 0) {
            // Should be unreachable except for rounding/accounting corruption; keep funds safe by not reverting settlement.
            treasury;
        }
    }

    function _remainingSideTotal(uint256 challengeId, Side side) internal view returns (uint256 total) {
        address[] storage accounts = _contributors[challengeId][side];
        for (uint256 i = 0; i < accounts.length; i++) {
            total += remainingContribution(challengeId, side, accounts[i]);
        }
    }
}
