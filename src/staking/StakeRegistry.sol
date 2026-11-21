// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IStakeRegistry} from "./IStakeRegistry.sol";
import {IERC20} from "../token/IERC20.sol";
import {SafeERC20} from "../token/SafeERC20.sol";

/// @notice Generic ERC20 stake and bond ledger for protocol contexts.
/// @dev This contract intentionally does not hardcode HNY. It tracks one configured
///      ERC20 token and lets authorized modules lock/release/slash deposited stake
///      by context and lock id.
contract StakeRegistry is IStakeRegistry {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error NotOwner();
    error NotManager();
    error InsufficientWithdrawable();
    error InsufficientLocked();

    IERC20 public immutable override stakeToken;
    address public owner;

    mapping(address => bool) public managers;
    uint256 public totalDeposited;

    mapping(address => uint256) private _totalBalance;
    mapping(address => uint256) private _totalLocked;
    mapping(address => mapping(bytes32 => uint256)) private _lockedByContext;
    mapping(address => mapping(bytes32 => mapping(bytes32 => uint256))) private _locks;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ManagerSet(address indexed manager, bool enabled);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyManager() {
        if (!managers[msg.sender]) revert NotManager();
        _;
    }

    constructor(IERC20 stakeToken_, address owner_) {
        if (address(stakeToken_) == address(0) || owner_ == address(0)) revert ZeroAddress();
        stakeToken = stakeToken_;
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setManager(address manager, bool enabled) external onlyOwner {
        if (manager == address(0)) revert ZeroAddress();
        managers[manager] = enabled;
        emit ManagerSet(manager, enabled);
    }

    function totalBalanceOf(address account) external view override returns (uint256) {
        return _totalBalance[account];
    }

    function lockedBalanceOf(address account) external view override returns (uint256) {
        return _totalLocked[account];
    }

    function withdrawableBalanceOf(address account) public view override returns (uint256) {
        return _totalBalance[account] - _totalLocked[account];
    }

    function lockedBalanceOf(address account, bytes32 context) external view override returns (uint256) {
        return _lockedByContext[account][context];
    }

    function lockedBalanceOf(address account, bytes32 context, bytes32 lockId)
        external
        view
        override
        returns (uint256)
    {
        return _locks[account][context][lockId];
    }

    function deposit(uint256 amount) external override {
        if (amount == 0) revert ZeroAmount();
        _totalBalance[msg.sender] += amount;
        totalDeposited += amount;
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    function depositFor(address account, uint256 amount) external override onlyManager {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 expectedBalance = totalDeposited + amount;
        if (stakeToken.balanceOf(address(this)) < expectedBalance) revert InsufficientWithdrawable();
        _totalBalance[account] += amount;
        totalDeposited = expectedBalance;
        emit Deposited(account, amount);
    }

    function withdraw(uint256 amount) external override {
        if (amount == 0) revert ZeroAmount();
        if (withdrawableBalanceOf(msg.sender) < amount) revert InsufficientWithdrawable();
        _totalBalance[msg.sender] -= amount;
        totalDeposited -= amount;
        stakeToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function allocate(address account, bytes32 context, bytes32 lockId, uint256 amount) external override onlyManager {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (withdrawableBalanceOf(account) < amount) revert InsufficientWithdrawable();

        _totalLocked[account] += amount;
        _lockedByContext[account][context] += amount;
        _locks[account][context][lockId] += amount;

        emit Allocated(account, context, lockId, amount);
    }

    function release(address account, bytes32 context, bytes32 lockId, uint256 amount) external override onlyManager {
        _decreaseLock(account, context, lockId, amount);
        emit Released(account, context, lockId, amount);
    }

    function slash(address account, bytes32 context, bytes32 lockId, address recipient, uint256 amount)
        external
        override
        onlyManager
    {
        _transferLocked(account, context, lockId, recipient, amount);
        emit Slashed(account, context, lockId, recipient, amount);
    }

    function spendLocked(address account, bytes32 context, bytes32 lockId, address recipient, uint256 amount)
        external
        override
        onlyManager
    {
        _transferLocked(account, context, lockId, recipient, amount);
        emit Spent(account, context, lockId, recipient, amount);
    }

    function _transferLocked(address account, bytes32 context, bytes32 lockId, address recipient, uint256 amount)
        internal
    {
        if (recipient == address(0)) revert ZeroAddress();
        _decreaseLock(account, context, lockId, amount);
        _totalBalance[account] -= amount;
        totalDeposited -= amount;
        stakeToken.safeTransfer(recipient, amount);
    }

    function _decreaseLock(address account, bytes32 context, bytes32 lockId, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_locks[account][context][lockId] < amount) revert InsufficientLocked();

        _locks[account][context][lockId] -= amount;
        _lockedByContext[account][context] -= amount;
        _totalLocked[account] -= amount;
    }
}
