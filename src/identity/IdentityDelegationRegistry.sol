// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIdentityDelegationRegistry} from "./IIdentityDelegationRegistry.sol";

/// @notice Minimal identity-root to operational-wallet delegation registry.
/// @dev The identity root self-authorizes hot/delegate keys. If an account has no delegate mapping,
///      it is its own identity root, allowing casual users to stake directly.
contract IdentityDelegationRegistry is IIdentityDelegationRegistry {
    error ZeroAddress();
    error DelegateAlreadyAssigned(address currentRoot);
    error NotDelegate();

    mapping(address delegate => address root) public delegatedRootOf;
    mapping(address root => mapping(address delegate => bool enabled)) public isDelegateOf;

    event DelegateSet(address indexed root, address indexed delegate, bool enabled);

    function setDelegate(address delegate, bool enabled) external {
        if (delegate == address(0)) revert ZeroAddress();
        address currentRoot = delegatedRootOf[delegate];
        if (enabled) {
            if (currentRoot != address(0) && currentRoot != msg.sender) revert DelegateAlreadyAssigned(currentRoot);
            delegatedRootOf[delegate] = msg.sender;
            isDelegateOf[msg.sender][delegate] = true;
        } else {
            if (currentRoot != msg.sender || !isDelegateOf[msg.sender][delegate]) revert NotDelegate();
            delete delegatedRootOf[delegate];
            delete isDelegateOf[msg.sender][delegate];
        }
        emit DelegateSet(msg.sender, delegate, enabled);
    }

    function renounceDelegation() external {
        address root = delegatedRootOf[msg.sender];
        if (root == address(0) || !isDelegateOf[root][msg.sender]) revert NotDelegate();
        delete delegatedRootOf[msg.sender];
        delete isDelegateOf[root][msg.sender];
        emit DelegateSet(root, msg.sender, false);
    }

    function identityRootOf(address account) external view returns (address root) {
        root = delegatedRootOf[account];
        return root == address(0) ? account : root;
    }
}
