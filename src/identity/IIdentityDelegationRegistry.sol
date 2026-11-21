// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IIdentityDelegationRegistry {
    function identityRootOf(address account) external view returns (address root);
    function isDelegateOf(address root, address delegate) external view returns (bool);
}
