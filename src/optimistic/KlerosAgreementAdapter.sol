// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../token/IERC20.sol";

interface IKlerosAgreementCore {
    function pinakion() external view returns (address);
    function arbitrationCost(bytes calldata extraData, IERC20 feeToken) external view returns (uint256);
    function createDispute(uint256 choices, bytes calldata extraData, IERC20 feeToken, uint256 amount)
        external
        returns (uint256);
}

/// @notice Single-Agreement bridge from Aragon's arbitrator interface to Honey-funded Kleros.
/// @dev Fresh deployment only. Configure Agreement with its optional app-fees cashier disabled.
contract KlerosAgreementAdapter {
    error InvalidConfiguration();
    error AgreementOnly();
    error CoreOnly();
    error UnknownDispute();
    error InvalidRuling();
    error NotFinal();
    error AlreadyFinal();
    error TransferFailed();
    error UnsupportedChoices();
    error EarlyEvidenceCloseUnsupported();

    struct Dispute {
        uint256 coreId;
        uint256 agreementRuling;
        bool exists;
        bool finalised;
    }

    IKlerosAgreementCore public immutable core;
    IERC20 public immutable honey;
    address public immutable agreement;
    bytes public extraData;
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => uint256) public agreementDisputeByCore;

    event DisputeCreated(uint256 indexed disputeId, uint256 indexed coreId, bytes metadata);
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, bytes evidence);
    event RulingReceived(
        uint256 indexed disputeId, uint256 indexed coreId, uint256 klerosRuling, uint256 agreementRuling
    );

    modifier onlyAgreement() {
        if (msg.sender != agreement) revert AgreementOnly();
        _;
    }

    constructor(IKlerosAgreementCore core_, IERC20 honey_, address agreement_, bytes memory extraData_) {
        if (address(core_).code.length == 0 || address(honey_).code.length == 0 || agreement_.code.length == 0) {
            revert InvalidConfiguration();
        }
        if (core_.pinakion() != address(honey_)) revert InvalidConfiguration();
        core = core_;
        honey = honey_;
        agreement = agreement_;
        extraData = extraData_;
    }

    function getDisputeFees() external view returns (address recipient, IERC20 feeToken, uint256 feeAmount) {
        return (address(this), honey, core.arbitrationCost(extraData, honey));
    }

    /// @notice No subscription/cashier service is supplied by this adapter.
    function getSubscriptionFees(address)
        external
        view
        returns (address recipient, IERC20 feeToken, uint256 feeAmount)
    {
        return (address(0), honey, 0);
    }

    function createDispute(uint256 possibleRulings, bytes calldata metadata)
        external
        onlyAgreement
        returns (uint256 id)
    {
        if (possibleRulings != 2) revert UnsupportedChoices();
        // Detect reconfiguration of the upgradeable core before taking participant funds.
        if (core.pinakion() != address(honey)) revert InvalidConfiguration();
        uint256 fee = core.arbitrationCost(extraData, honey);
        if (!honey.transferFrom(msg.sender, address(this), fee)) revert TransferFailed();
        if (!honey.approve(address(core), fee)) revert TransferFailed();
        uint256 coreId = core.createDispute(2, extraData, honey, fee);
        // Agreement keys challenges by arbitrator dispute ID alone. Namespace by this adapter
        // instead of restarting at zero alongside historical Celeste IDs.
        id = uint256(keccak256(abi.encode(address(this), coreId)));
        if (disputes[id].exists) revert InvalidConfiguration();
        disputes[id] = Dispute(coreId, 0, true, false);
        agreementDisputeByCore[coreId] = id;
        emit DisputeCreated(id, coreId, metadata);
    }

    function submitEvidence(uint256 id, address submitter, bytes calldata evidence) external onlyAgreement {
        Dispute storage dispute = disputes[id];
        if (!dispute.exists) revert UnknownDispute();
        if (dispute.finalised) revert AlreadyFinal();
        emit EvidenceSubmitted(id, submitter, evidence);
    }

    /// @dev Kleros periods cannot be shortened by this bridge. Agreement's automatic attempt
    /// is best-effort; explicit early-close callers receive a visible unsupported result.
    function closeEvidencePeriod(uint256 id) external view onlyAgreement {
        if (!disputes[id].exists) revert UnknownDispute();
        revert EarlyEvidenceCloseUnsupported();
    }

    /// @notice Native Kleros callback after its appeal/finality lifecycle has completed.
    function rule(uint256 coreId, uint256 ruling) external {
        if (msg.sender != address(core)) revert CoreOnly();
        uint256 id = agreementDisputeByCore[coreId];
        Dispute storage dispute = disputes[id];
        if (!dispute.exists || dispute.coreId != coreId) revert UnknownDispute();
        if (dispute.finalised) revert AlreadyFinal();
        if (ruling > 2) revert InvalidRuling();
        // Kleros: 0 refuse, 1 challenger, 2 submitter. Agreement: 2 refuse, 3/4 parties.
        dispute.agreementRuling = ruling + 2;
        dispute.finalised = true;
        emit RulingReceived(id, coreId, ruling, dispute.agreementRuling);
    }

    /// @notice Agreement pulls the final ruling during resolve(); reading never executes an action.
    function rule(uint256 id) external view onlyAgreement returns (address subject, uint256 ruling) {
        Dispute storage dispute = disputes[id];
        if (!dispute.exists) revert UnknownDispute();
        if (!dispute.finalised) revert NotFinal();
        return (agreement, dispute.agreementRuling);
    }
}
