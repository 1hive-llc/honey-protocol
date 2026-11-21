// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../token/IERC20.sol";
import {IApproveAndCallFallBack} from "../token/IApproveAndCallFallBack.sol";

/// @notice Test HNY that mirrors the production Gnosis Honey MiniMe transaction surface.
/// @dev This is intentionally not a full historical MiniMe implementation. Snapshot reads
///      return the current value, but approval semantics and approveAndCall match the parts
///      the app/transaction path must handle for existing HNY.
contract MockMiniMeHoney is IERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals = 18;
    uint256 public totalSupply;
    uint256 public immutable creationBlock;
    bool public transfersEnabled = true;
    address public controller;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        creationBlock = block.number;
        controller = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function generateTokens(address owner, uint256 amount) external returns (bool) {
        totalSupply += amount;
        balanceOf[owner] += amount;
        emit Transfer(address(0), owner, amount);
        return true;
    }

    function destroyTokens(address owner, uint256 amount) external returns (bool) {
        require(balanceOf[owner] >= amount, "MINIME_BALANCE");
        balanceOf[owner] -= amount;
        totalSupply -= amount;
        emit Transfer(owner, address(0), amount);
        return true;
    }

    function enableTransfers(bool enabled) external {
        transfersEnabled = enabled;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        require(transfersEnabled, "MINIME_TRANSFERS_DISABLED");
        require(amount == 0 || allowance[msg.sender][spender] == 0, "MINIME_APPROVE_NONZERO");
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveAndCall(address spender, uint256 amount, bytes calldata extraData) external returns (bool) {
        require(approve(spender, amount));
        IApproveAndCallFallBack(spender).receiveApproval(msg.sender, amount, address(this), extraData);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(transfersEnabled, "MINIME_TRANSFERS_DISABLED");
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(transfersEnabled, "MINIME_TRANSFERS_DISABLED");
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "MINIME_ALLOWANCE");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function balanceOfAt(address owner, uint256) external view returns (uint256) {
        return balanceOf[owner];
    }

    function totalSupplyAt(uint256) external view returns (uint256) {
        return totalSupply;
    }

    function version() external pure returns (string memory) {
        return "HNY-MINIME-TEST";
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "MINIME_ZERO_TO");
        require(balanceOf[from] >= amount, "MINIME_BALANCE");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
