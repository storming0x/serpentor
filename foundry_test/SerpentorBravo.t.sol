// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/IERC20.sol";
import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {SerpentorBravo, ProposalAction, Proposal} from "./interfaces/SerpentorBravo.sol";
import {Timelock} from "./interfaces/Timelock.sol";
import {GovToken} from "./utils/GovToken.sol";

contract SerpentorBravoTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    SerpentorBravo private serpentor;

    Timelock private timelock;
    GovToken private token;
    uint public constant GRACE_PERIOD = 14 days;
    uint public constant MINIMUM_DELAY = 2 days;
    uint public constant MAXIMUM_DELAY = 30 days;
    uint public constant VOTING_PERIOD = 5760; // about 24 hours
    uint public constant THRESHOLD = 100e18;
    uint public constant QUORUM_VOTES = 1000e18;
    uint public constant VOTING_DELAY = 20000;
    uint8 public constant DECIMALS = 18;
    uint public delay = 2 days;

    address public queen = address(1);
    address public proposer = address(2);
    address public smallVoter = address(3);
    address public mediumVoter = address(4);
    address public whaleVoter = address(5);
    address public whitelistedProposer = address(6);

    // events
    event ProposalCreated(
        uint256 id,
        address indexed proposer,
        ProposalAction[] actions,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
  
    function setUp() public {
        // deploy token
        token = new GovToken(DECIMALS);
        console.log("address for token: ", address(token));

        // deploy timelock
        bytes memory timelockArgs = abi.encode(queen, delay);
        timelock = Timelock(vyperDeployer.deployContract("src/", "Timelock", timelockArgs));
        console.log("address for timelock: ", address(timelock));

        bytes memory serpentorArgs = abi.encode(
            address(timelock), 
            address(token),
            VOTING_PERIOD,
            VOTING_DELAY,
            THRESHOLD,
            QUORUM_VOTES,
            0 // initialProposalId
        );
        serpentor = SerpentorBravo(vyperDeployer.deployContract("src/", "SerpentorBravo", serpentorArgs));
        console.log("address for gov contract: ", address(serpentor));

        // label for traces
        vm.label(address(serpentor), "SerpentorBravo");
        vm.label(address(timelock), "Timelock");
        vm.label(address(token), "Token");

        // hand over control to queen
        hoax(address(vyperDeployer));
        serpentor.setPendingQueen(queen);
        hoax(queen);
        serpentor.acceptThrone();

        // setup voting balances
        deal(address(token), proposer, THRESHOLD + 1);
        deal(address(token), smallVoter, 1e18);
        deal(address(token), mediumVoter, 10e18);
        deal(address(token), whaleVoter, 200e18);
        deal(address(token), address(serpentor), 1000e18);
    }

    function testSetup() public {
        assertNeq(address(serpentor), address(0));
        assertNeq(address(token), address(0));
        assertNeq(address(timelock), address(0));

        assertEq(address(serpentor.timelock()), address(timelock));
        assertEq(address(serpentor.token()), address(token));
        assertEq(serpentor.votingPeriod(), VOTING_PERIOD);
        assertEq(serpentor.votingDelay(), VOTING_DELAY);
        assertEq(serpentor.proposalThreshold(), THRESHOLD);
        assertEq(serpentor.quorumVotes(), QUORUM_VOTES);
        assertEq(serpentor.initialProposalId(), 0);
        assertEq(serpentor.queen(), queen);
        assertEq(serpentor.pendingQueen(), address(0));
        // check tests have correct starting balance of tokens
        assertEq(token.balanceOf(address(this)), 30000 * 10**uint256(DECIMALS));
        assertEq(token.balanceOf(proposer), THRESHOLD + 1);
        assertEq(token.balanceOf(smallVoter), 1e18);
        assertEq(token.balanceOf(mediumVoter), 10e18);
        assertEq(token.balanceOf(whaleVoter), 200e18);
        assertEq(token.balanceOf(whitelistedProposer), 0);
    }

    function testCannotProposeBelowThreshold(uint256 votes) public {
        vm.assume(votes <= THRESHOLD);
        // setup
        address yoloProposer = address(0xBEEF);
        deal(address(token), yoloProposer, votes);
    
        skip(2 days);
        assertEq(token.getPriorVotes(yoloProposer, block.number), votes);
        ProposalAction[] memory actions;
        vm.expectRevert(bytes("!threshold"));

        //execute
        hoax(yoloProposer);
        serpentor.propose(actions, "test proposal");
    }

    function testCannotProposeZeroActions(uint256 votes) public {
        vm.assume(votes > THRESHOLD && votes < type(uint128).max);
        // setup
        address yoloProposer = address(0xBEEF);
        deal(address(token), yoloProposer, votes);
    
        skip(2 days);
        assertEq(token.getPriorVotes(yoloProposer, block.number), votes);
        ProposalAction[] memory actions;
        vm.expectRevert(bytes("!no_actions"));

        //execute
        hoax(yoloProposer);
        serpentor.propose(actions, "test proposal");
    }

     function testCannotProposeTooManyActions(uint256 votes, uint8 size) public {
        uint256 maxActions = serpentor.proposalMaxActions();
        uint256 threshold = serpentor.proposalThreshold();
        // if maxActions is a big number, tests runs out of gas
        vm.assume(votes > threshold && size >= maxActions && size <= maxActions + 5);
        // setup
        address yoloProposer = address(0xBEEF);
        address grantee = address(0xABCD);
        uint256 transferAmount = 1e18;
        deal(address(token), yoloProposer, votes);
    
        skip(2 days);
        assertEq(token.getPriorVotes(yoloProposer, block.number), votes);
        // transfer 1e18 token to grantee
        bytes memory callData = abi.encodeWithSelector(IERC20.transfer.selector, grantee, transferAmount);

        ProposalAction memory testAction = ProposalAction({
            target: address(token),
            amount: 0,
            signature: "",
            callData: callData
        });

        ProposalAction[] memory actions = new ProposalAction[](size);
        // fill up action array
        for (uint i = 0; i < size; i++)
             actions[i] = testAction;
       
        vm.expectRevert(bytes("!too_many_actions"));

        //execute
        hoax(yoloProposer);
        serpentor.propose(actions, "test proposal");
    }

    function testCanSubmitProposal(uint256 votes) public {
        uint256 threshold = serpentor.proposalThreshold();
        // if maxActions is a big number, tests runs out of gas
        vm.assume(votes > threshold && votes < type(uint128).max);
        // setup
        address grantProposer = address(0xBEEF);
        address grantee = address(0xABCD);
        uint256 transferAmount = 1e18;
        deal(address(token), grantProposer, votes);
    
        skip(2 days);
        assertEq(token.getPriorVotes(grantProposer, block.number), votes);
        // transfer 1e18 token to grantee
        bytes memory callData = abi.encodeWithSelector(IERC20.transfer.selector, grantee, transferAmount);

        ProposalAction memory testAction = ProposalAction({
            target: address(token),
            amount: 0,
            signature: "",
            callData: callData
        });

        ProposalAction[] memory actions = new ProposalAction[](1);
        actions[0] = testAction;
        //setup for event checks
        uint256 expectedStartBlock = block.number + serpentor.votingDelay();
        uint256 expectedEndBlock = expectedStartBlock + serpentor.votingPeriod();
        vm.expectEmit(false, true, false, false);
        emit ProposalCreated(1, grantProposer, actions, expectedStartBlock, expectedEndBlock, "send grant to contributor");
    
        // execute
        hoax(grantProposer);
        uint256 proposalId = serpentor.propose(actions, "send grant to contributor");
        Proposal memory proposal = serpentor.proposals(proposalId);

        // asserts
        assertEq(serpentor.proposalCount(), proposalId);
        assertEq(serpentor.latestProposalIds(grantProposer), proposalId);
        assertEq(proposal.id, proposalId);
        assertEq(proposal.proposer, grantProposer);
        assertEq(proposal.eta, 0);
        assertEq(proposal.actions.length, actions.length);
        assertEq(proposal.startBlock, expectedStartBlock);
        assertEq(proposal.endBlock, expectedEndBlock);
        assertEq(proposal.forVotes, 0);
        assertEq(proposal.againstVotes, 0);
        assertEq(proposal.abstainVotes, 0);
        assertFalse(proposal.canceled);
        assertFalse(proposal.executed);
    }

}
