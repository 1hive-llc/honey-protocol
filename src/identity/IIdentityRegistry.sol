// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IIdentityRegistry {
    enum IdentityStatus {
        None,
        Verified,
        Revoked
    }

    function isVerified(address account) external view returns (bool);
    function hasUniqueUserId(address account) external view returns (bool);
    function uniqueUserId(address account) external view returns (address);
    function statusOf(address identity) external view returns (IdentityStatus);
}
