// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ICOMP} from "../src/interfaces/ICOMP.sol";
import {IBravoGovernance} from "../src/interfaces/IBravoGovernance.sol";
import {IBalancerQueriesHelper} from "../src/interfaces/IBalancerQueriesHelper.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";

import {TrustSetup} from "../src/TrustSetup.sol";

contract BaseFixture is Test {
    ///////////////////////////// Constants ///////////////////////////////
    uint256 constant TIMELOCK_DELAY = 172800;

    // comptroller holds currently 1_631_724e18 COMP
    uint256 constant COMP_INVESTED_AMOUNT = 500_000e18;

    address constant MEV_BOT_BUYER = address(655656);

    address constant PROPOSER_GOVERNANCE = 0x36cc7B13029B5DEe4034745FB4F24034f3F2ffc6;

    address constant VOTER_CASTER_PENN_BLOCKCHAIN = 0x070341aA5Ed571f0FB2c4a5641409B1A46b4961b;
    address constant VOTER_CASTER_WINTERMUTE_GOVERNANCE = 0xB933AEe47C438f22DE0747D57fc239FE37878Dd1;
    address constant VOTER_CASTER_MONETSUPPLY = 0x8d07D225a769b7Af3A923481E1FdF49180e6A265;
    address constant VOTER_CASTER_A = 0xed11e5eA95a5A3440fbAadc4CC404C56D0a5bb04;
    address constant VOTER_CASTER_B = 0xdC1F98682F4F8a5c6d54F345F448437b83f5E432;
    address constant VOTER_CASTER_C = 0x13BDaE8c5F0fC40231F0E6A4ad70196F59138548;
    address constant VOTER_CASTER_D = 0x54A37d93E57c5DA659F508069Cf65A381b61E189;

    IBravoGovernance public constant COMPOUND_GOVERNANCE = IBravoGovernance(0xc0Da02939E1441F497fd74F78cE7Decb17B66529);
    address public constant COMPOUND_GOVERNANCE_IMPLEMENTATION = 0xeF3B6E9e13706A8F01fe98fdCf66335dc5CfdEED;

    ICOMP constant COMP = ICOMP(0xc00e94Cb662C3520282E6f5717214004A7f26888);

    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant GOLD = IERC20(0x9DeB0fc809955b79c85e82918E8586d3b7d2695a);

    IBalancerQueriesHelper constant BALANCER_QUERIES_HELPER =
        IBalancerQueriesHelper(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);

    TrustSetup trustSetup;

    function setUp() public {
        vm.createSelectFork("mainnet", 19_961_089);

        trustSetup = new TrustSetup();

        vm.label(address(trustSetup), "TRUST_SETUP");
        vm.label(address(COMPOUND_GOVERNANCE), "COMPOUND_GOVERNANCE");
        vm.label(COMPOUND_GOVERNANCE_IMPLEMENTATION, "COMPOUND_GOVERNANCE_IMPLEMENTATION");
        vm.label(trustSetup.COMPTROLLER(), "COMPTROLLER");
        vm.label(trustSetup.COMPOUND_TIMELOCK(), "COMPOUND_TIMELOCK");
        vm.label(address(COMP), "COMP_TOKEN");
        vm.label(address(trustSetup.BALANCER_VAULT()), "BALANCER_VAULT");
        vm.label(address(trustSetup.BPT()), "BPT");
        vm.label(address(trustSetup.GAUGE()), "GAUGE");
        vm.label(address(WETH), "WETH");
        vm.label(address(GOLD), "GOLD");
        vm.label(address(trustSetup.GOLD_COMP()), "GOLD_COMP");
        vm.label(address(trustSetup.ORACLE_COMP_ETH()), "ORACLE_COMP_ETH");
        vm.label(address(trustSetup.ORACLE_COMP_USD()), "ORACLE_COMP_USD");
        vm.label(address(trustSetup.ORACLE_ETH_USD()), "ORACLE_ETH_USD");
    }

    function grantCompAndInvest(uint256 _compToInvest) internal returns (uint256 proposalId) {
        address[] memory targets = new address[](2);
        targets[0] = trustSetup.COMPTROLLER();
        targets[1] = address(trustSetup);
        uint256[] memory values = new uint256[](2);
        string[] memory signatures = new string[](2);
        signatures[0] = "_grantComp(address,uint256)";
        signatures[1] = "invest(uint256)";
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encode(address(trustSetup), _compToInvest);
        calldatas[1] = abi.encode(_compToInvest);
        string memory description = "grant comp to trust setup contract and trigger invest";
        vm.prank(PROPOSER_GOVERNANCE);
        proposalId = COMPOUND_GOVERNANCE.propose(targets, values, signatures, calldatas, description);
    }

    function queueCommenceDivestment(uint256 _bptBalance) internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        targets[0] = address(trustSetup);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        signatures[0] = "commenceDivestment(uint256)";
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encode(_bptBalance);
        string memory description = "commence divestment";
        vm.prank(PROPOSER_GOVERNANCE);
        proposalId = COMPOUND_GOVERNANCE.propose(targets, values, signatures, calldatas, description);
    }

    function queueCompleteDivestment() internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        targets[0] = address(trustSetup);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        signatures[0] = "completeDivestment()";
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "complete divestment";
        vm.prank(PROPOSER_GOVERNANCE);
        proposalId = COMPOUND_GOVERNANCE.propose(targets, values, signatures, calldatas, description);
    }

    /// @dev Mirror proposal state being on a successful state to be able to queue
    function voteForProposal(uint256 _proposalId) internal {
        vm.roll(block.number + COMPOUND_GOVERNANCE.votingDelay() + 1);
        assertEq(COMPOUND_GOVERNANCE.state(_proposalId), uint8(IBravoGovernance.ProposalState.Active));

        // 0=against, 1=for, 2=abstain
        vm.prank(PROPOSER_GOVERNANCE);
        COMPOUND_GOVERNANCE.castVote(_proposalId, 1);
        vm.prank(VOTER_CASTER_PENN_BLOCKCHAIN);
        COMPOUND_GOVERNANCE.castVote(_proposalId, 1);
        vm.prank(VOTER_CASTER_WINTERMUTE_GOVERNANCE);
        COMPOUND_GOVERNANCE.castVote(_proposalId, 1);
        vm.prank(VOTER_CASTER_MONETSUPPLY);
        COMPOUND_GOVERNANCE.castVote(_proposalId, 1);
        vm.prank(VOTER_CASTER_A);
        COMPOUND_GOVERNANCE.castVote(_proposalId, 1);
        vm.prank(VOTER_CASTER_B);
        COMPOUND_GOVERNANCE.castVote(_proposalId, 1);
        vm.prank(VOTER_CASTER_C);
        COMPOUND_GOVERNANCE.castVote(_proposalId, 1);
        vm.prank(VOTER_CASTER_D);
        COMPOUND_GOVERNANCE.castVote(_proposalId, 1);

        vm.roll(block.number + COMPOUND_GOVERNANCE.votingPeriod());
        assertEq(COMPOUND_GOVERNANCE.state(_proposalId), uint8(IBravoGovernance.ProposalState.Succeeded));
    }

    function syncOracleUpdateAt() internal {
        // manipulate the updateAt value of the oracle for testing purposes
        // otherwise may trigger stale oracle error since it has sensitive time dependency
        (, int256 answer,,,) = trustSetup.ORACLE_COMP_USD().latestRoundData();
        vm.mockCall(
            address(trustSetup.ORACLE_COMP_USD()),
            abi.encodeWithSelector(IOracle.latestRoundData.selector),
            abi.encode(
                0,
                answer, // answer
                0,
                block.timestamp, // updatedAt
                0
            )
        );

        (, answer,,,) = trustSetup.ORACLE_ETH_USD().latestRoundData();
        vm.mockCall(
            address(trustSetup.ORACLE_ETH_USD()),
            abi.encodeWithSelector(IOracle.latestRoundData.selector),
            abi.encode(
                0,
                answer, // answer
                0,
                block.timestamp, // updatedAt
                0
            )
        );
    }
}
