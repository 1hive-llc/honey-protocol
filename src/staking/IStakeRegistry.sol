// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../token/IERC20.sol";

/// @notice Generic ERC20 staking ledger for Honey v2 protocol stake/bond contexts.
/// @dev The token is configured at deployment, initially expected to be HNY on Gnosis,
///      but the interface intentionally does not hardcode Honey/HNY naming.
interface IStakeRegistry {
    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event Allocated(address indexed account, bytes32 indexed context, bytes32 indexed lockId, uint256 amount);
    event Released(address indexed account, bytes32 indexed context, bytes32 indexed lockId, uint256 amount);
    event Slashed(
        address indexed account, bytes32 indexed context, bytes32 indexed lockId, address recipient, uint256 amount
    );
    event Spent(
        address indexed account, bytes32 indexed context, bytes32 indexed lockId, address recipient, uint256 amount
    );

    function stakeToken() external view returns (IERC20);

    function totalBalanceOf(address account) external view returns (uint256);
    function lockedBalanceOf(address account) external view returns (uint256);
    function withdrawableBalanceOf(address account) external view returns (uint256);
    function lockedBalanceOf(address account, bytes32 context) external view returns (uint256);
    function lockedBalanceOf(address account, bytes32 context, bytes32 lockId) external view returns (uint256);

    function deposit(uint256 amount) external;

    /// @notice Credit tokens already transferred into the registry to `account`.
    /// @dev Intended for tightly-scoped adapters such as MiniMe approveAndCall receivers.
    function depositFor(address account, uint256 amount) external;

    function withdraw(uint256 amount) external;

    /// @notice Lock existing deposited stake into a protocol context.
    function allocate(address account, bytes32 context, bytes32 lockId, uint256 amount) external;

    /// @notice Release a context lock back to the account's withdrawable stake balance.
    function release(address account, bytes32 context, bytes32 lockId, uint256 amount) external;

    /// @notice Slash a context lock and send tokens to a recipient or treasury.
    function slash(address account, bytes32 context, bytes32 lockId, address recipient, uint256 amount) external;

    /// @notice Spend a context lock on protocol fees without treating it as a penalty.
    function spendLocked(address account, bytes32 context, bytes32 lockId, address recipient, uint256 amount) external;
}
