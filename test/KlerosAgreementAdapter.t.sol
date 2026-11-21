// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {KlerosAgreementAdapter, IKlerosAgreementCore} from "../src/optimistic/KlerosAgreementAdapter.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IERC20} from "../src/token/IERC20.sol";

contract AgreementCoreStub {
    address public pinakion;
    uint256 public nextId;

    constructor(address token) {
        pinakion = token;
    }

    function arbitrationCost(bytes calldata, IERC20) external pure returns (uint256) {
        return 10 ether;
    }

    function createDispute(uint256, bytes calldata, IERC20 token, uint256 amount) external returns (uint256) {
        require(token.transferFrom(msg.sender, address(this), amount));
        return nextId++;
    }

    function deliver(KlerosAgreementAdapter adapter, uint256 id, uint256 ruling) external {
        adapter.rule(id, ruling);
    }
}

contract KlerosAgreementAdapterTest is Test {
    MockERC20 honey;
    AgreementCoreStub core;
    KlerosAgreementAdapter adapter;

    function setUp() public {
        honey = new MockERC20("Honey", "HNY");
        core = new AgreementCoreStub(address(honey));
        adapter = new KlerosAgreementAdapter(IKlerosAgreementCore(address(core)), honey, address(this), hex"01");
        honey.mint(address(this), 100 ether);
        honey.approve(address(adapter), 100 ether);
    }

    function testPullsQuotedHoneyAndNamespacesIds() public {
        (address recipient, IERC20 token, uint256 cost) = adapter.getDisputeFees();
        assertEq(recipient, address(adapter));
        assertEq(address(token), address(honey));
        assertEq(cost, 10 ether);
        uint256 id = adapter.createDispute(2, "context");
        assertEq(id, uint256(keccak256(abi.encode(address(adapter), uint256(0)))));
        assertEq(honey.balanceOf(address(core)), cost);
        assertEq(honey.balanceOf(address(adapter)), 0);
        assertEq(honey.allowance(address(adapter), address(core)), 0);
        assertTrue(adapter.createDispute(2, "second") != id);
    }

    function testFuzzMapsOnlyFinalNativeRulings(uint8 choice) public {
        choice = uint8(bound(choice, 0, 2));
        uint256 id = adapter.createDispute(2, "context");
        vm.expectRevert(KlerosAgreementAdapter.NotFinal.selector);
        adapter.rule(id);
        core.deliver(adapter, 0, choice);
        (address subject, uint256 ruling) = adapter.rule(id);
        assertEq(subject, address(this));
        assertEq(ruling, uint256(choice) + 2);
        vm.expectRevert(KlerosAgreementAdapter.AlreadyFinal.selector);
        core.deliver(adapter, 0, choice);
    }

    function testRejectsUnknownForgedAndInvalidCallbacks() public {
        uint256 id = adapter.createDispute(2, "context");
        vm.expectRevert(KlerosAgreementAdapter.CoreOnly.selector);
        adapter.rule(0, 1);
        vm.expectRevert(KlerosAgreementAdapter.UnknownDispute.selector);
        core.deliver(adapter, 999, 1);
        vm.expectRevert(KlerosAgreementAdapter.InvalidRuling.selector);
        core.deliver(adapter, 0, 3);
        vm.expectRevert(KlerosAgreementAdapter.NotFinal.selector);
        adapter.rule(id);
    }

    function testOnlyAgreementCanCreateOrAttributeEvidence() public {
        uint256 id = adapter.createDispute(2, "context");
        vm.startPrank(address(123));
        vm.expectRevert(KlerosAgreementAdapter.AgreementOnly.selector);
        adapter.createDispute(2, "context");
        vm.expectRevert(KlerosAgreementAdapter.AgreementOnly.selector);
        adapter.submitEvidence(id, address(this), "forged");
        vm.stopPrank();
        adapter.submitEvidence(id, address(123), "legitimate forwarding");
        vm.expectRevert(KlerosAgreementAdapter.EarlyEvidenceCloseUnsupported.selector);
        adapter.closeEvidencePeriod(id);
    }

    function testInsufficientAllowanceAndUnsupportedChoicesDoNotConsumeFunds() public {
        honey.approve(address(adapter), 0);
        vm.expectRevert();
        adapter.createDispute(2, "context");
        assertEq(honey.balanceOf(address(core)), 0);
        vm.expectRevert(KlerosAgreementAdapter.UnsupportedChoices.selector);
        adapter.createDispute(3, "context");
    }
}
