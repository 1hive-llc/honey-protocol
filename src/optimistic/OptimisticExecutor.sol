// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../token/IERC20.sol";
import {SafeERC20} from "../token/SafeERC20.sol";
import {IOptimisticArbitrator} from "./IOptimisticArbitrator.sol";

contract OptimisticExecutor {
    using SafeERC20 for IERC20;
    error NotOwner();
    error ZeroAddress();
    error EmptyBatch();
    error ArrayLengthMismatch();
    error BatchTooLarge();
    error ActionNotFound();
    error ChallengeNotFound();
    error NotSubmitter();
    error NotScheduled();
    error NotChallenged();
    error NotDisputed();
    error NotCancellable();
    error NotExecutable();
    error ChallengeWindowClosed();
    error ResponseWindowOpen();
    error ResponseWindowClosed();
    error SettlementTooHigh();
    error UnsafeDuration();
    error IncorrectValue();
    error RulingNotReady();
    error InvalidRuling();
    error Expired();
    error NotExpired();
    error CallFailed(uint256 index, bytes returndata);
    error ReentrantCall();

    enum ActionStatus {
        None,
        Scheduled,
        Challenged,
        Disputed,
        Allowed,
        Rejected,
        Executed,
        Cancelled
    }

    struct Agreement {
        IERC20 bondToken;
        IOptimisticArbitrator arbitrator;
        uint256 submitterBond;
        uint256 challengerBond;
        uint64 challengeDuration;
        uint64 responseDuration;
        uint64 executionWindow;
        string metadataURI;
        bool enabled;
    }

    struct Action {
        address submitter;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        bytes32 actionHash;
        string metadataURI;
        uint256 agreementId;
        IERC20 bondToken;
        IOptimisticArbitrator arbitrator;
        uint256 submitterBond;
        uint64 executionWindow;
        uint64 submittedAt;
        uint64 executableAfter;
        uint64 expiresAt;
        ActionStatus status;
        uint256 challengeId;
        uint256 disputeId;
    }

    struct Challenge {
        uint256 actionId;
        address challenger;
        uint256 challengerBond;
        uint256 settlementOffer;
        uint64 responseDeadline;
        string evidenceURI;
        bool exists;
    }

    address public owner;
    uint256 public constant MAX_BATCH_SIZE = 25;
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 public nextAgreementId = 1;
    uint256 public nextActionId = 1;
    uint256 public nextChallengeId = 1;
    uint256 private reentrancyStatus = NOT_ENTERED;

    mapping(uint256 agreementId => Agreement agreement) public agreements;
    mapping(uint256 actionId => Action action) private actions;
    mapping(uint256 challengeId => Challenge challenge) public challenges;
    mapping(bytes32 disputeKey => uint256 actionId) public actionByDispute;

    event OwnerChanged(address indexed previousOwner, address indexed newOwner);
    event AgreementCreated(uint256 indexed agreementId, string metadataURI);
    event AgreementUpdated(uint256 indexed agreementId, string metadataURI, bool enabled);
    event ActionScheduled(
        uint256 indexed actionId,
        uint256 indexed agreementId,
        address indexed submitter,
        bytes32 actionHash,
        string metadataURI
    );
    event ActionChallenged(
        uint256 indexed actionId,
        uint256 indexed challengeId,
        address indexed challenger,
        uint256 settlementOffer,
        string evidenceURI
    );
    event SettlementAccepted(uint256 indexed actionId, uint256 indexed challengeId, uint256 settlementAmount);
    event ActionDisputed(
        uint256 indexed actionId, uint256 indexed challengeId, uint256 indexed disputeId, string evidenceURI
    );
    event DefaultClaimed(uint256 indexed actionId, uint256 indexed challengeId);
    event ActionAllowed(uint256 indexed actionId, uint256 indexed disputeId);
    event ActionRejected(uint256 indexed actionId, uint256 indexed disputeId);
    event ActionCancelled(uint256 indexed actionId);
    event ActionExecuted(uint256 indexed actionId);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (reentrancyStatus == ENTERED) revert ReentrantCall();
        reentrancyStatus = ENTERED;
        _;
        reentrancyStatus = NOT_ENTERED;
    }

    constructor(address initialOwner) {
        owner = initialOwner == address(0) ? msg.sender : initialOwner;
        emit OwnerChanged(address(0), owner);
    }

    receive() external payable {}

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function createAgreement(
        IERC20 bondToken,
        IOptimisticArbitrator arbitrator,
        uint256 submitterBond,
        uint256 challengerBond,
        uint64 challengeDuration,
        uint64 responseDuration,
        uint64 executionWindow,
        string calldata metadataURI
    ) external onlyOwner returns (uint256 agreementId) {
        if (address(bondToken) == address(0) || address(arbitrator) == address(0)) {
            revert ZeroAddress();
        }
        _validateDurations(challengeDuration, responseDuration, executionWindow);
        agreementId = nextAgreementId++;
        agreements[agreementId] = Agreement({
            bondToken: bondToken,
            arbitrator: arbitrator,
            submitterBond: submitterBond,
            challengerBond: challengerBond,
            challengeDuration: challengeDuration,
            responseDuration: responseDuration,
            executionWindow: executionWindow,
            metadataURI: metadataURI,
            enabled: true
        });
        emit AgreementCreated(agreementId, metadataURI);
    }

    function setAgreement(
        uint256 agreementId,
        IERC20 bondToken,
        IOptimisticArbitrator arbitrator,
        uint256 submitterBond,
        uint256 challengerBond,
        uint64 challengeDuration,
        uint64 responseDuration,
        uint64 executionWindow,
        string calldata metadataURI,
        bool enabled
    ) external onlyOwner {
        if (agreementId == 0 || agreementId >= nextAgreementId) revert ActionNotFound();
        if (address(bondToken) == address(0) || address(arbitrator) == address(0)) revert ZeroAddress();
        _validateDurations(challengeDuration, responseDuration, executionWindow);
        agreements[agreementId] = Agreement({
            bondToken: bondToken,
            arbitrator: arbitrator,
            submitterBond: submitterBond,
            challengerBond: challengerBond,
            challengeDuration: challengeDuration,
            responseDuration: responseDuration,
            executionWindow: executionWindow,
            metadataURI: metadataURI,
            enabled: enabled
        });
        emit AgreementUpdated(agreementId, metadataURI, enabled);
    }

    function scheduleAction(
        uint256 agreementId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string calldata metadataURI
    ) external nonReentrant returns (uint256 actionId) {
        Agreement storage agreement = agreements[agreementId];
        if (!agreement.enabled) revert ActionNotFound();
        if (targets.length == 0) revert EmptyBatch();
        if (targets.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        if (targets.length != values.length || targets.length != calldatas.length) revert ArrayLengthMismatch();

        actionId = nextActionId++;
        Action storage action = actions[actionId];
        action.submitter = msg.sender;
        action.agreementId = agreementId;
        action.bondToken = agreement.bondToken;
        action.arbitrator = agreement.arbitrator;
        action.submitterBond = agreement.submitterBond;
        action.executionWindow = agreement.executionWindow;
        action.submittedAt = uint64(block.timestamp);
        action.executableAfter = uint64(block.timestamp) + agreement.challengeDuration;
        action.expiresAt = action.executableAfter + agreement.executionWindow;
        action.status = ActionStatus.Scheduled;
        action.metadataURI = metadataURI;

        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] == address(0)) revert ZeroAddress();
            action.targets.push(targets[i]);
            action.values.push(values[i]);
            action.calldatas.push(calldatas[i]);
        }
        bytes32 callsHash = keccak256(abi.encode(targets, values, calldatas));
        action.actionHash = keccak256(
            abi.encode(
                block.chainid,
                address(this),
                actionId,
                agreementId,
                msg.sender,
                keccak256(bytes(metadataURI)),
                callsHash
            )
        );

        if (action.submitterBond > 0) {
            action.bondToken.safeTransferFrom(msg.sender, address(this), action.submitterBond);
        }

        emit ActionScheduled(actionId, agreementId, msg.sender, action.actionHash, metadataURI);
    }

    function challengeAction(uint256 actionId, uint256 settlementOffer, string calldata evidenceURI)
        external
        nonReentrant
        returns (uint256 challengeId)
    {
        Action storage action = _getAction(actionId);
        if (action.status != ActionStatus.Scheduled) revert NotScheduled();
        if (block.timestamp >= action.executableAfter) revert ChallengeWindowClosed();
        if (settlementOffer > action.submitterBond) revert SettlementTooHigh();

        Agreement storage agreement = agreements[action.agreementId];
        uint256 challengerBond = agreement.challengerBond;

        challengeId = nextChallengeId++;
        challenges[challengeId] = Challenge({
            actionId: actionId,
            challenger: msg.sender,
            challengerBond: challengerBond,
            settlementOffer: settlementOffer,
            responseDeadline: uint64(block.timestamp) + agreement.responseDuration,
            evidenceURI: evidenceURI,
            exists: true
        });

        action.status = ActionStatus.Challenged;
        action.challengeId = challengeId;

        if (challengerBond > 0) {
            action.bondToken.safeTransferFrom(msg.sender, address(this), challengerBond);
        }

        emit ActionChallenged(actionId, challengeId, msg.sender, settlementOffer, evidenceURI);
    }

    function acceptSettlement(uint256 actionId) external nonReentrant {
        Action storage action = _getAction(actionId);
        if (action.submitter != msg.sender) revert NotSubmitter();
        if (action.status != ActionStatus.Challenged) revert NotChallenged();

        Challenge storage challenge = _getChallenge(action.challengeId);
        if (block.timestamp >= challenge.responseDeadline) revert ResponseWindowClosed();
        action.status = ActionStatus.Cancelled;

        uint256 returnedToSubmitter = action.submitterBond - challenge.settlementOffer;
        if (challenge.settlementOffer > 0) {
            _transferBond(action.bondToken, challenge.challenger, challenge.settlementOffer);
        }
        if (returnedToSubmitter > 0) _transferBond(action.bondToken, action.submitter, returnedToSubmitter);
        if (challenge.challengerBond > 0) {
            _transferBond(action.bondToken, challenge.challenger, challenge.challengerBond);
        }

        emit SettlementAccepted(actionId, action.challengeId, challenge.settlementOffer);
    }

    function disputeAction(uint256 actionId, string calldata evidenceURI)
        external
        nonReentrant
        returns (uint256 disputeId)
    {
        Action storage action = _getAction(actionId);
        if (action.submitter != msg.sender) revert NotSubmitter();
        if (action.status != ActionStatus.Challenged) revert NotChallenged();
        Challenge storage challenge = _getChallenge(action.challengeId);
        if (block.timestamp >= challenge.responseDeadline) revert ResponseWindowClosed();

        action.status = ActionStatus.Disputed;

        bytes memory metadata =
            abi.encode(actionId, action.challengeId, action.metadataURI, challenge.evidenceURI, evidenceURI);
        disputeId = action.arbitrator.createDispute(2, metadata);
        action.arbitrator.submitEvidence(disputeId, action.submitter, bytes(evidenceURI));
        action.arbitrator.submitEvidence(disputeId, challenge.challenger, bytes(challenge.evidenceURI));

        action.disputeId = disputeId;
        actionByDispute[_disputeKey(action.arbitrator, disputeId)] = actionId;

        emit ActionDisputed(actionId, action.challengeId, disputeId, evidenceURI);
    }

    function claimDefault(uint256 actionId) external nonReentrant {
        Action storage action = _getAction(actionId);
        if (action.status != ActionStatus.Challenged) revert NotChallenged();
        Challenge storage challenge = _getChallenge(action.challengeId);
        if (block.timestamp < challenge.responseDeadline) revert ResponseWindowOpen();

        action.status = ActionStatus.Rejected;

        if (action.submitterBond > 0) _transferBond(action.bondToken, challenge.challenger, action.submitterBond);
        if (challenge.challengerBond > 0) {
            _transferBond(action.bondToken, challenge.challenger, challenge.challengerBond);
        }

        emit DefaultClaimed(actionId, action.challengeId);
    }

    function resolve(uint256 actionId) external nonReentrant {
        Action storage action = _getAction(actionId);
        if (action.status != ActionStatus.Disputed) revert NotDisputed();
        Challenge storage challenge = _getChallenge(action.challengeId);
        if (actionByDispute[_disputeKey(action.arbitrator, action.disputeId)] != actionId) revert ActionNotFound();

        (bool ruled, uint256 ruling) = action.arbitrator.getRuling(action.disputeId);
        if (!ruled) revert RulingNotReady();

        if (ruling == 1) {
            action.status = ActionStatus.Allowed;
            action.expiresAt = uint64(block.timestamp) + action.executionWindow;
            if (challenge.challengerBond > 0) {
                _transferBond(action.bondToken, action.submitter, challenge.challengerBond);
            }
            emit ActionAllowed(actionId, action.disputeId);
        } else if (ruling == 2) {
            action.status = ActionStatus.Rejected;
            if (action.submitterBond > 0) _transferBond(action.bondToken, challenge.challenger, action.submitterBond);
            if (challenge.challengerBond > 0) {
                _transferBond(action.bondToken, challenge.challenger, challenge.challengerBond);
            }
            emit ActionRejected(actionId, action.disputeId);
        } else {
            revert InvalidRuling();
        }
    }

    function cancel(uint256 actionId) external nonReentrant {
        Action storage action = _getAction(actionId);
        if (action.submitter != msg.sender) revert NotSubmitter();
        if (action.status != ActionStatus.Scheduled) revert NotScheduled();

        action.status = ActionStatus.Cancelled;
        if (action.submitterBond > 0) _transferBond(action.bondToken, action.submitter, action.submitterBond);
        emit ActionCancelled(actionId);
    }

    function cancelExpired(uint256 actionId) external nonReentrant {
        Action storage action = _getAction(actionId);
        if (action.status != ActionStatus.Scheduled && action.status != ActionStatus.Allowed) revert NotCancellable();
        if (block.timestamp <= action.expiresAt) revert NotExpired();

        action.status = ActionStatus.Cancelled;
        if (action.submitterBond > 0) _transferBond(action.bondToken, action.submitter, action.submitterBond);
        emit ActionCancelled(actionId);
    }

    function execute(uint256 actionId) external payable nonReentrant {
        Action storage action = _getAction(actionId);
        if (action.status == ActionStatus.Scheduled) {
            if (block.timestamp < action.executableAfter) revert NotExecutable();
        } else if (action.status != ActionStatus.Allowed) {
            revert NotExecutable();
        }
        if (block.timestamp > action.expiresAt) revert Expired();
        if (msg.value != _totalValue(action)) revert IncorrectValue();

        action.status = ActionStatus.Executed;
        if (action.submitterBond > 0) _transferBond(action.bondToken, action.submitter, action.submitterBond);

        for (uint256 i = 0; i < action.targets.length; i++) {
            (bool ok, bytes memory returndata) = action.targets[i].call{value: action.values[i]}(action.calldatas[i]);
            if (!ok) revert CallFailed(i, returndata);
        }

        emit ActionExecuted(actionId);
    }

    function getAction(uint256 actionId)
        external
        view
        returns (
            address submitter,
            bytes32 actionHash,
            string memory metadataURI,
            uint256 agreementId,
            uint64 submittedAt,
            uint64 executableAfter,
            uint64 expiresAt,
            ActionStatus status,
            uint256 challengeId,
            uint256 disputeId
        )
    {
        Action storage action = _getAction(actionId);
        return (
            action.submitter,
            action.actionHash,
            action.metadataURI,
            action.agreementId,
            action.submittedAt,
            action.executableAfter,
            action.expiresAt,
            action.status,
            action.challengeId,
            action.disputeId
        );
    }

    function getActionCalls(uint256 actionId)
        external
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        Action storage action = _getAction(actionId);
        return (action.targets, action.values, action.calldatas);
    }

    function _getAction(uint256 actionId) internal view returns (Action storage action) {
        action = actions[actionId];
        if (action.status == ActionStatus.None) revert ActionNotFound();
    }

    function _getChallenge(uint256 challengeId) internal view returns (Challenge storage challenge) {
        challenge = challenges[challengeId];
        if (!challenge.exists) revert ChallengeNotFound();
    }

    function _transferBond(IERC20 token, address to, uint256 amount) internal {
        token.safeTransfer(to, amount);
    }

    function _validateDurations(uint64 challengeDuration, uint64 responseDuration, uint64 executionWindow)
        internal
        pure
    {
        if (challengeDuration == 0 || responseDuration == 0 || executionWindow == 0) revert UnsafeDuration();
    }

    function _totalValue(Action storage action) internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < action.values.length; i++) {
            totalValue += action.values[i];
        }
    }

    function _disputeKey(IOptimisticArbitrator arbitrator, uint256 disputeId) internal pure returns (bytes32) {
        return keccak256(abi.encode(arbitrator, disputeId));
    }
}
