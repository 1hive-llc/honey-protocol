// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ContentChallengeManager} from "../content/ContentChallengeManager.sol";
import {IERC20} from "../token/IERC20.sol";
import {IApproveAndCallFallBack} from "../token/IApproveAndCallFallBack.sol";
import {IStakeRegistry} from "./IStakeRegistry.sol";

/// @notice MiniMe approveAndCall receiver for one-transaction Honey stake deposits.
/// @dev The adapter must be authorized as a StakeRegistry manager so it can credit
///      tokens transferred directly into the registry on behalf of the Honey holder.
contract HoneyApproveAndCallAdapter is IApproveAndCallFallBack {
    enum Intent {
        DepositOnly,
        OpenContentChallenge,
        FundContentChallengeRestore
    }

    struct OpenContentChallengeIntent {
        ContentChallengeManager manager;
        bytes32 contentId;
        bytes32 localCaseIdHash;
        address respondent;
        string evidenceURI;
    }

    struct FundContentChallengeRestoreIntent {
        ContentChallengeManager manager;
        uint256 challengeId;
        uint256 contributionAmount;
        string evidenceURI;
    }

    error InvalidToken();
    error InvalidAmount();
    error InvalidIntent();
    error TransferFailed();

    IERC20 public immutable honey;
    IStakeRegistry public immutable stakeRegistry;

    event HoneyIntentExecuted(address indexed account, Intent indexed intent, uint256 amount, bytes data);

    constructor(IERC20 honey_, IStakeRegistry stakeRegistry_) {
        honey = honey_;
        stakeRegistry = stakeRegistry_;
    }

    function receiveApproval(address from, uint256 amount, address token, bytes calldata data) external override {
        if (msg.sender != address(honey) || token != address(honey)) revert InvalidToken();
        if (from == address(0) || amount == 0) revert InvalidAmount();

        (Intent intent, bytes memory payload) =
            data.length == 0 ? (Intent.DepositOnly, bytes("")) : abi.decode(data, (Intent, bytes));

        bool ok = honey.transferFrom(from, address(stakeRegistry), amount);
        if (!ok) revert TransferFailed();
        stakeRegistry.depositFor(from, amount);

        if (intent == Intent.DepositOnly) {
            // Deposit was the full user intent.
        } else if (intent == Intent.OpenContentChallenge) {
            OpenContentChallengeIntent memory openIntent = abi.decode(payload, (OpenContentChallengeIntent));
            openIntent.manager
                .openChallengeFor(
                    from,
                    openIntent.contentId,
                    openIntent.localCaseIdHash,
                    openIntent.respondent,
                    openIntent.evidenceURI
                );
        } else if (intent == Intent.FundContentChallengeRestore) {
            FundContentChallengeRestoreIntent memory fundIntent =
                abi.decode(payload, (FundContentChallengeRestoreIntent));
            fundIntent.manager
                .fundRestoreFor(fundIntent.challengeId, from, fundIntent.contributionAmount, fundIntent.evidenceURI);
        } else {
            revert InvalidIntent();
        }

        emit HoneyIntentExecuted(from, intent, amount, data);
    }
}
