// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockMiniMeHoney} from "../src/mocks/MockMiniMeHoney.sol";
import {HoneyApproveAndCallAdapter} from "../src/staking/HoneyApproveAndCallAdapter.sol";
import {StakeRegistry} from "../src/staking/StakeRegistry.sol";
import {StakeContext} from "../src/staking/StakeContext.sol";

contract StakeRegistryTest is Test {
    MockERC20 token;
    StakeRegistry registry;

    address owner = address(0xA11CE);
    address manager = address(0xB0B);
    address user = address(0xCAFE);
    address recipient = address(0xDAD);

    bytes32 lockA = keccak256("lock-a");
    bytes32 lockB = keccak256("lock-b");

    function setUp() public {
        token = new MockERC20("Stake Token", "STK");
        registry = new StakeRegistry(token, owner);

        vm.prank(owner);
        registry.setManager(manager, true);

        token.mint(user, 1_000 ether);
        vm.prank(user);
        token.approve(address(registry), type(uint256).max);
    }

    function testDepositAndWithdraw() public {
        vm.prank(user);
        registry.deposit(100 ether);

        assertEq(registry.totalBalanceOf(user), 100 ether);
        assertEq(registry.lockedBalanceOf(user), 0);
        assertEq(registry.withdrawableBalanceOf(user), 100 ether);
        assertEq(registry.totalDeposited(), 100 ether);
        assertEq(token.balanceOf(address(registry)), 100 ether);

        vm.prank(user);
        registry.withdraw(40 ether);

        assertEq(registry.totalBalanceOf(user), 60 ether);
        assertEq(registry.withdrawableBalanceOf(user), 60 ether);
        assertEq(registry.totalDeposited(), 60 ether);
        assertEq(token.balanceOf(user), 940 ether);
    }

    function testOnlyManagerCanDepositForTokensAlreadyReceived() public {
        token.mint(address(registry), 25 ether);

        vm.prank(user);
        vm.expectRevert(StakeRegistry.NotManager.selector);
        registry.depositFor(user, 25 ether);

        vm.prank(manager);
        registry.depositFor(user, 25 ether);

        assertEq(registry.totalBalanceOf(user), 25 ether);
        assertEq(registry.withdrawableBalanceOf(user), 25 ether);
        assertEq(registry.totalDeposited(), 25 ether);
    }

    function testDepositForRequiresTokenBalanceBacking() public {
        vm.prank(manager);
        vm.expectRevert(StakeRegistry.InsufficientWithdrawable.selector);
        registry.depositFor(user, 1 ether);
    }

    function testMiniMeApproveRequiresZeroReset() public {
        MockMiniMeHoney hny = new MockMiniMeHoney("Honey", "HNY");
        hny.mint(user, 100 ether);

        vm.startPrank(user);
        hny.approve(address(registry), 10 ether);
        vm.expectRevert();
        hny.approve(address(registry), 20 ether);
        hny.approve(address(registry), 0);
        hny.approve(address(registry), 20 ether);
        vm.stopPrank();

        assertEq(hny.allowance(user, address(registry)), 20 ether);
    }

    function testApproveAndCallAdapterDepositsInOneTransaction() public {
        MockMiniMeHoney hny = new MockMiniMeHoney("Honey", "HNY");
        StakeRegistry miniMeRegistry = new StakeRegistry(hny, owner);
        HoneyApproveAndCallAdapter adapter = new HoneyApproveAndCallAdapter(hny, miniMeRegistry);

        vm.prank(owner);
        miniMeRegistry.setManager(address(adapter), true);

        hny.mint(user, 100 ether);
        vm.prank(user);
        hny.approveAndCall(
            address(adapter), 30 ether, abi.encode(HoneyApproveAndCallAdapter.Intent.DepositOnly, bytes(""))
        );

        assertEq(hny.balanceOf(user), 70 ether);
        assertEq(hny.balanceOf(address(miniMeRegistry)), 30 ether);
        assertEq(miniMeRegistry.totalBalanceOf(user), 30 ether);
        assertEq(miniMeRegistry.withdrawableBalanceOf(user), 30 ether);
        assertEq(miniMeRegistry.totalDeposited(), 30 ether);
        assertEq(hny.allowance(user, address(adapter)), 0);
    }

    function testManagerCanAllocateReleaseAndSlashContexts() public {
        _deposit(user, 300 ether);

        vm.startPrank(manager);
        registry.allocate(user, StakeContext.IDENTITY_BOND, lockA, 100 ether);
        registry.allocate(user, StakeContext.HUMAN_COURT_ACTIVE, lockB, 60 ether);
        vm.stopPrank();

        assertEq(registry.totalBalanceOf(user), 300 ether);
        assertEq(registry.lockedBalanceOf(user), 160 ether);
        assertEq(registry.withdrawableBalanceOf(user), 140 ether);
        assertEq(registry.lockedBalanceOf(user, StakeContext.IDENTITY_BOND), 100 ether);
        assertEq(registry.lockedBalanceOf(user, StakeContext.HUMAN_COURT_ACTIVE), 60 ether);
        assertEq(registry.lockedBalanceOf(user, StakeContext.IDENTITY_BOND, lockA), 100 ether);

        vm.prank(manager);
        registry.release(user, StakeContext.IDENTITY_BOND, lockA, 40 ether);

        assertEq(registry.lockedBalanceOf(user), 120 ether);
        assertEq(registry.withdrawableBalanceOf(user), 180 ether);
        assertEq(registry.lockedBalanceOf(user, StakeContext.IDENTITY_BOND, lockA), 60 ether);

        vm.prank(manager);
        registry.slash(user, StakeContext.HUMAN_COURT_ACTIVE, lockB, recipient, 25 ether);

        assertEq(registry.totalBalanceOf(user), 275 ether);
        assertEq(registry.lockedBalanceOf(user), 95 ether);
        assertEq(registry.withdrawableBalanceOf(user), 180 ether);
        assertEq(token.balanceOf(recipient), 25 ether);
    }

    function testManagerCanSpendLockedStakeForProtocolFees() public {
        _deposit(user, 100 ether);

        vm.startPrank(manager);
        registry.allocate(user, StakeContext.CONTENT_CHALLENGE, lockA, 80 ether);
        registry.spendLocked(user, StakeContext.CONTENT_CHALLENGE, lockA, recipient, 15 ether);
        vm.stopPrank();

        assertEq(registry.totalBalanceOf(user), 85 ether);
        assertEq(registry.lockedBalanceOf(user), 65 ether);
        assertEq(registry.lockedBalanceOf(user, StakeContext.CONTENT_CHALLENGE, lockA), 65 ether);
        assertEq(registry.withdrawableBalanceOf(user), 20 ether);
        assertEq(token.balanceOf(recipient), 15 ether);
    }

    function testCannotWithdrawLockedStake() public {
        _deposit(user, 100 ether);
        vm.prank(manager);
        registry.allocate(user, StakeContext.STAKE_COURT_ACTIVE, lockA, 80 ether);

        vm.prank(user);
        vm.expectRevert(StakeRegistry.InsufficientWithdrawable.selector);
        registry.withdraw(21 ether);

        vm.prank(user);
        registry.withdraw(20 ether);
        assertEq(registry.totalBalanceOf(user), 80 ether);
        assertEq(registry.lockedBalanceOf(user), 80 ether);
        assertEq(registry.withdrawableBalanceOf(user), 0);
    }

    function testUnauthorizedLockMutationsRevert() public {
        _deposit(user, 100 ether);

        vm.prank(user);
        vm.expectRevert(StakeRegistry.NotManager.selector);
        registry.allocate(user, StakeContext.IDENTITY_BOND, lockA, 10 ether);

        vm.prank(user);
        vm.expectRevert(StakeRegistry.NotManager.selector);
        registry.release(user, StakeContext.IDENTITY_BOND, lockA, 10 ether);

        vm.prank(user);
        vm.expectRevert(StakeRegistry.NotManager.selector);
        registry.slash(user, StakeContext.IDENTITY_BOND, lockA, recipient, 10 ether);

        vm.prank(user);
        vm.expectRevert(StakeRegistry.NotManager.selector);
        registry.spendLocked(user, StakeContext.IDENTITY_BOND, lockA, recipient, 10 ether);
    }

    function testOnlyOwnerCanSetManagersAndTransferOwnership() public {
        address newManager = address(0x1234);
        vm.prank(user);
        vm.expectRevert(StakeRegistry.NotOwner.selector);
        registry.setManager(newManager, true);

        vm.prank(owner);
        registry.transferOwnership(user);

        vm.prank(owner);
        vm.expectRevert(StakeRegistry.NotOwner.selector);
        registry.setManager(newManager, true);

        vm.prank(user);
        registry.setManager(newManager, true);
        assertTrue(registry.managers(newManager));
    }

    function testInsufficientAndZeroAmountReverts() public {
        vm.prank(user);
        vm.expectRevert(StakeRegistry.ZeroAmount.selector);
        registry.deposit(0);

        _deposit(user, 10 ether);

        vm.prank(manager);
        vm.expectRevert(StakeRegistry.InsufficientWithdrawable.selector);
        registry.allocate(user, StakeContext.IDENTITY_BOND, lockA, 11 ether);

        vm.prank(manager);
        vm.expectRevert(StakeRegistry.ZeroAmount.selector);
        registry.allocate(user, StakeContext.IDENTITY_BOND, lockA, 0);

        vm.prank(manager);
        registry.allocate(user, StakeContext.IDENTITY_BOND, lockA, 10 ether);

        vm.prank(manager);
        vm.expectRevert(StakeRegistry.InsufficientLocked.selector);
        registry.release(user, StakeContext.IDENTITY_BOND, lockA, 11 ether);
    }

    function testMultiLockSameContext() public {
        _deposit(user, 100 ether);

        vm.startPrank(manager);
        registry.allocate(user, StakeContext.OPTIMISTIC_EXECUTION_BOND, lockA, 25 ether);
        registry.allocate(user, StakeContext.OPTIMISTIC_EXECUTION_BOND, lockB, 35 ether);
        vm.stopPrank();

        assertEq(registry.lockedBalanceOf(user, StakeContext.OPTIMISTIC_EXECUTION_BOND), 60 ether);
        assertEq(registry.lockedBalanceOf(user, StakeContext.OPTIMISTIC_EXECUTION_BOND, lockA), 25 ether);
        assertEq(registry.lockedBalanceOf(user, StakeContext.OPTIMISTIC_EXECUTION_BOND, lockB), 35 ether);

        vm.prank(manager);
        registry.release(user, StakeContext.OPTIMISTIC_EXECUTION_BOND, lockA, 25 ether);

        assertEq(registry.lockedBalanceOf(user, StakeContext.OPTIMISTIC_EXECUTION_BOND), 35 ether);
        assertEq(registry.lockedBalanceOf(user, StakeContext.OPTIMISTIC_EXECUTION_BOND, lockA), 0);
        assertEq(registry.lockedBalanceOf(user, StakeContext.OPTIMISTIC_EXECUTION_BOND, lockB), 35 ether);
    }

    function testFuzzDepositAllocateReleaseSlashInvariant(
        uint96 depositAmount,
        uint96 identityAmount,
        uint96 courtAmount,
        uint96 releaseAmount,
        uint96 slashAmount
    ) public {
        vm.assume(depositAmount > 0);
        uint256 depositValue = uint256(depositAmount);
        token.mint(user, depositValue);
        vm.prank(user);
        registry.deposit(depositValue);

        uint256 identityValue = bound(uint256(identityAmount), 0, depositValue);
        uint256 remaining = depositValue - identityValue;
        uint256 courtValue = bound(uint256(courtAmount), 0, remaining);

        vm.startPrank(manager);
        if (identityValue > 0) registry.allocate(user, StakeContext.IDENTITY_BOND, lockA, identityValue);
        if (courtValue > 0) registry.allocate(user, StakeContext.HUMAN_COURT_ACTIVE, lockB, courtValue);

        if (identityValue > 0) {
            uint256 releaseValue = bound(uint256(releaseAmount), 0, identityValue);
            if (releaseValue > 0) registry.release(user, StakeContext.IDENTITY_BOND, lockA, releaseValue);
            identityValue -= releaseValue;
        }

        if (courtValue > 0) {
            uint256 slashValue = bound(uint256(slashAmount), 0, courtValue);
            if (slashValue > 0) registry.slash(user, StakeContext.HUMAN_COURT_ACTIVE, lockB, recipient, slashValue);
            courtValue -= slashValue;
        }
        vm.stopPrank();

        assertEq(registry.totalBalanceOf(user), registry.withdrawableBalanceOf(user) + registry.lockedBalanceOf(user));
        assertEq(registry.lockedBalanceOf(user), identityValue + courtValue);
    }

    function _deposit(address account, uint256 amount) internal {
        vm.prank(account);
        registry.deposit(amount);
    }
}
