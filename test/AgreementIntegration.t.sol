// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {KlerosCore_TestBase} from "../vendor/kleros-v2/contracts/test/foundry/KlerosCore_TestBase.sol";
import {KlerosAgreementAdapter, IKlerosAgreementCore} from "../src/optimistic/KlerosAgreementAdapter.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20 as HoneyToken} from "../src/token/IERC20.sol";

interface LegacyKernel {
    function initialize(address aclBase, address permissionsCreator) external;
    function acl() external view returns (address);
    function newAppInstance(bytes32 appId, address appBase, bytes calldata data, bool makeDefault)
        external
        returns (address);
}

interface LegacyACL {
    function createPermission(address who, address where, bytes32 role, address manager) external;
}

interface LegacyAgreement {
    function initialize(
        address arbitrator,
        bool cashier,
        string calldata title,
        bytes calldata content,
        address factory
    ) external;
    function changeSetting(address arbitrator, bool cashier, string calldata title, bytes calldata content) external;
    function activate(
        address app,
        address token,
        uint64 duration,
        uint256 actionCollateral,
        uint256 challengeCollateral
    ) external;
    function sign(uint256 setting) external;
    function challengeAction(uint256 action, uint256 offer, bool finished, bytes calldata context) external;
    function disputeAction(uint256 action, bool finished) external;
    function resolve(uint256 disputeId) external;
    function closeAction(uint256 action) external;
}

interface LegacyDisputable {
    function initialize() external;
    function submit() external returns (uint256);
    function outcome() external view returns (uint256);
}

interface LegacyFactory {
    function getInstance(address token) external view returns (address);
}

interface LegacyStaking {
    function stake(uint256 amount, bytes calldata data) external;
    function allowManager(address manager, uint256 allowance, bytes calldata data) external;
    function lockedBalanceOf(address user) external view returns (uint256);
}

/// @notice Opt-in proof against unmodified pinned Agreement, Kernel, ACL and staking bytecode.
contract AgreementIntegrationTest is KlerosCore_TestBase {
    string artifacts;
    MockERC20 honey;
    LegacyAgreement agreement;
    LegacyDisputable app;
    LegacyStaking staking;
    KlerosAgreementAdapter adapter;

    function _deploy(string memory name, bytes memory args) internal returns (address deployed) {
        bytes memory code = abi.encodePacked(vm.getCode(string.concat(artifacts, "/", name, ".json")), args);
        assembly ("memory-safe") { deployed := create(0, add(code, 32), mload(code)) }
        require(deployed != address(0), "legacy deployment failed");
    }

    function setUp() public override {
        artifacts = vm.envOr("HONEY_AGREEMENT_ARTIFACTS", string(""));
        if (bytes(artifacts).length == 0) {
            vm.skip(true);
            return;
        }
        super.setUp();
        honey = new MockERC20("Honey", "HNY");
        vm.startPrank(owner);
        core.changePinakion(IERC20(address(honey)));
        core.changeAcceptedFeeTokens(IERC20(address(honey)), true);
        ratesConverter.changeCurrencyRates(IERC20(address(honey)), uint64(0.01 ether), 18);
        vm.stopPrank();
        LegacyKernel kernel = LegacyKernel(_deploy("Kernel", abi.encode(false)));
        kernel.initialize(_deploy("ACL", ""), address(this));
        LegacyACL acl = LegacyACL(kernel.acl());
        acl.createPermission(address(this), address(kernel), keccak256("APP_MANAGER_ROLE"), address(this));
        agreement = LegacyAgreement(kernel.newAppInstance(keccak256("agreement"), _deploy("Agreement", ""), "", false));
        app = LegacyDisputable(
            kernel.newAppInstance(keccak256("disputable"), _deploy("DisputableFixture", ""), "", false)
        );
        address factory = _deploy("StakingFactory", "");
        adapter = new KlerosAgreementAdapter(
            IKlerosAgreementCore(address(core)),
            HoneyToken(address(honey)),
            address(agreement),
            abi.encode(uint96(1), uint256(3), uint256(1))
        );
        agreement.initialize(address(adapter), false, "Honey agreement", "terms", factory);
        acl.createPermission(address(this), address(agreement), keccak256("CHANGE_AGREEMENT_ROLE"), address(this));
        acl.createPermission(address(this), address(agreement), keccak256("MANAGE_DISPUTABLE_ROLE"), address(this));
        acl.createPermission(address(agreement), address(app), keccak256("SET_AGREEMENT_ROLE"), address(this));
        acl.createPermission(crowdfunder1, address(app), keccak256("CHALLENGE_ROLE"), address(this));
        app.initialize();
        agreement.activate(address(app), address(honey), 1 days, 100 ether, 200 ether);
        staking = LegacyStaking(LegacyFactory(factory).getInstance(address(honey)));
        honey.mint(disputer, 1000 ether);
        honey.mint(crowdfunder1, 1000 ether);
        honey.mint(staker1, 10_000 ether);
        vm.startPrank(disputer);
        honey.approve(address(staking), 100 ether);
        staking.stake(100 ether, "");
        staking.allowManager(address(agreement), 100 ether, "");
        honey.approve(address(agreement), 1000 ether);
        agreement.sign(1);
        vm.stopPrank();
        vm.prank(crowdfunder1);
        honey.approve(address(agreement), 1000 ether);
        vm.startPrank(staker1);
        honey.approve(address(core), 10_000 ether);
        core.setStake(1, 10_000 ether);
        vm.stopPrank();
    }

    function _resolve(uint256 choice) internal {
        vm.prank(disputer);
        uint256 action = app.submit();
        assertEq(action, 1);
        assertEq(staking.lockedBalanceOf(disputer), 100 ether);
        vm.prank(crowdfunder1);
        agreement.challengeAction(action, 0, true, "challenge evidence");
        assertEq(honey.balanceOf(address(agreement)), 209 ether);
        vm.prank(disputer);
        agreement.disputeAction(action, true);
        // Submitter fee went to Core; challenger fee and collateral stay in Agreement.
        assertEq(honey.balanceOf(address(core)), 10_009 ether);
        assertEq(honey.balanceOf(address(agreement)), 209 ether);
        uint256 disputeId = adapter.agreementDisputeByCore(0);
        vm.expectRevert();
        agreement.resolve(disputeId);
        vm.warp(block.timestamp + minStakingTime);
        sortitionModule.passPhase();
        vm.warp(block.timestamp + rngLookahead);
        sortitionModule.passPhase();
        core.draw(0, 3);
        vm.warp(block.timestamp + timesPerPeriod[0]);
        core.passPeriod(0);
        uint256[] memory votes = new uint256[](3);
        votes[1] = 1;
        votes[2] = 2;
        vm.prank(staker1);
        disputeKit.castVote(0, votes, choice, 0, "rationale");
        core.passPeriod(0);
        vm.warp(block.timestamp + timesPerPeriod[3]);
        core.passPeriod(0);
        core.executeRuling(0);
        agreement.resolve(disputeId);
        assertEq(app.outcome(), choice + 2);
        assertEq(honey.balanceOf(address(agreement)), 0);
    }

    function testSubmitterRulingReturnsChallengeEscrowAndUnlocksOnClose() public {
        _resolve(2);
        assertEq(honey.balanceOf(disputer), 1100 ether); // 1000 - 100 stake - 9 fee + 209 escrow
        assertEq(staking.lockedBalanceOf(disputer), 100 ether);
        agreement.closeAction(1);
        assertEq(staking.lockedBalanceOf(disputer), 0);
    }

    function testChallengerRulingSlashesActionCollateral() public {
        _resolve(1);
        assertEq(honey.balanceOf(crowdfunder1), 1100 ether);
        assertEq(staking.lockedBalanceOf(disputer), 0);
    }

    function testRefusedRulingSplitsFeesAndReturnsChallengeCollateral() public {
        _resolve(0);
        assertEq(honey.balanceOf(disputer), 895.5 ether);
        assertEq(honey.balanceOf(crowdfunder1), 995.5 ether);
        agreement.closeAction(1);
        assertEq(staking.lockedBalanceOf(disputer), 0);
    }

    function testSettingChangeRequiresACLAndNewSignature() public {
        vm.prank(disputer);
        vm.expectRevert();
        agreement.changeSetting(address(adapter), false, "unauthorized", "terms");
        agreement.changeSetting(address(adapter), false, "new terms", "terms v2");
        vm.prank(disputer);
        vm.expectRevert();
        app.submit();
        vm.startPrank(disputer);
        agreement.sign(2);
        assertEq(app.submit(), 1);
        vm.stopPrank();
    }
}
