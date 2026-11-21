// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIdentityRegistry} from "./IIdentityRegistry.sol";

contract IdentityRegistry is IIdentityRegistry {
    error NotOwner();
    error ZeroIdentity();
    error ZeroAccount();
    error UnknownIdentity();
    error AccountAlreadyLinked();

    address public owner;

    mapping(address account => address identity) private identityOfAccount;
    mapping(address identity => IdentityStatus status) private identityStatus;

    event OwnerChanged(address indexed previousOwner, address indexed newOwner);
    event IdentityVerified(address indexed identity);
    event AccountLinked(address indexed account, address indexed identity);
    event IdentityRevoked(address indexed identity);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address initialOwner) {
        owner = initialOwner == address(0) ? msg.sender : initialOwner;
        emit OwnerChanged(address(0), owner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAccount();
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function verifyIdentity(address identity, address[] calldata accounts) external onlyOwner {
        if (identity == address(0)) revert ZeroIdentity();
        identityStatus[identity] = IdentityStatus.Verified;
        emit IdentityVerified(identity);

        for (uint256 i = 0; i < accounts.length; i++) {
            _linkAccount(identity, accounts[i]);
        }
    }

    function linkAccount(address identity, address account) external onlyOwner {
        if (identityStatus[identity] == IdentityStatus.None) revert UnknownIdentity();
        _linkAccount(identity, account);
    }

    function revokeIdentity(address identity) external onlyOwner {
        if (identity == address(0)) revert ZeroIdentity();
        if (identityStatus[identity] == IdentityStatus.None) revert UnknownIdentity();
        identityStatus[identity] = IdentityStatus.Revoked;
        emit IdentityRevoked(identity);
    }

    function isVerified(address account) external view returns (bool) {
        address identity = identityOfAccount[account];
        return identity != address(0) && identityStatus[identity] == IdentityStatus.Verified;
    }

    function hasUniqueUserId(address account) external view returns (bool) {
        return identityOfAccount[account] != address(0);
    }

    function uniqueUserId(address account) external view returns (address) {
        return identityOfAccount[account];
    }

    function statusOf(address identity) external view returns (IdentityStatus) {
        return identityStatus[identity];
    }

    function _linkAccount(address identity, address account) internal {
        if (identity == address(0)) revert ZeroIdentity();
        if (account == address(0)) revert ZeroAccount();

        address currentIdentity = identityOfAccount[account];
        if (currentIdentity != address(0) && currentIdentity != identity) revert AccountAlreadyLinked();

        identityOfAccount[account] = identity;
        emit AccountLinked(account, identity);
    }
}
