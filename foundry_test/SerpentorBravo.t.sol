// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/IERC20.sol";
import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {SerpentorBravo, ProposalAction, Proposal, ProposalState} from "./interfaces/SerpentorBravo.sol";
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
    uint public constant QUORUM_VOTES = 500e18;
    uint public constant VOTING_DELAY = 20000;
    uint8 public constant DECIMALS = 18;
    uint public delay = 2 days;

    address public queen = address(1);
    address public proposer = address(2);
    address public smallVoter = address(3);
    address public mediumVoter = address(4);
    address public whaleVoter1 = address(5);
    address public whaleVoter2 = address(6);
    address public whitelistedProposer = address(7);
    address public knight = address(8);

    // events
    event ProposalCreated(
        uint256 id,
        address indexed proposer,
        ProposalAction[] actions,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event ProposalCanceled(uint256 proposalId);
  
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
        vm.label(proposer, "proposer");
        vm.label(smallVoter, "smallVoter");
        vm.label(mediumVoter, "mediumVoter");
        vm.label(whaleVoter1, "whaleVoter1");
        vm.label(whaleVoter2, "whaleVoter2");

        // setup coupled governance between serpentor and timelock
        hoax(address(vyperDeployer));
        serpentor.setPendingQueen(address(timelock));
        hoax(address(timelock));
        serpentor.acceptThrone();
        hoax(address(timelock));
        timelock.setPendingQueen(address(serpentor));
        hoax(address(serpentor));
        timelock.acceptThrone();
        hoax(address(timelock));
        serpentor.setKnight(knight);
        hoax(address(knight));
        serpentor.setWhitelistAccountExpiration(whitelistedProposer, block.timestamp + 300 days);

        // setup voting balances
        deal(address(token), proposer, THRESHOLD + 1);
        deal(address(token), smallVoter, 1e18);
        deal(address(token), mediumVoter, 10e18);
        deal(address(token), whaleVoter1, 300e18);
        deal(address(token), whaleVoter2, 250e18);
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
        assertEq(serpentor.queen(), address(timelock));
        assertEq(serpentor.pendingQueen(), address(0));
        assertEq(timelock.queen(), address(serpentor));
        assertEq(serpentor.knight(), knight);
        assertTrue(serpentor.isWhitelisted(whitelistedProposer));
        // check tests have correct starting balance of tokens
        assertEq(token.balanceOf(address(this)), 30000 * 10**uint256(DECIMALS));
        assertEq(token.balanceOf(proposer), THRESHOLD + 1);
        assertEq(token.balanceOf(smallVoter), 1e18);
        assertEq(token.balanceOf(mediumVoter), 10e18);
        assertEq(token.balanceOf(whaleVoter1), 300e18);
        assertEq(token.balanceOf(whaleVoter2), 250e18);
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
        uint8 state = serpentor.ordinalState(proposalId);

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
        assertTrue(state == uint8(ProposalState.PENDING));
    }

     function testCannotProposeIfLastProposalIsPending(uint256 votes) public {
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

        ProposalAction[] memory firstProposalActions = new ProposalAction[](1);
        firstProposalActions[0] = testAction;
    
        // setup first proposal
        hoax(grantProposer);
        uint256 proposalId = serpentor.propose(firstProposalActions, "send grant to contributor");
        uint8 state = serpentor.ordinalState(proposalId);
        assertTrue(state == uint8(ProposalState.PENDING));

        ProposalAction[] memory secondProposalActions = new ProposalAction[](1);
        secondProposalActions[0] = testAction;

        // execute
        vm.expectRevert(bytes("!latestPropId_state"));
        hoax(grantProposer);
        serpentor.propose(secondProposalActions, "send second grant to contributor");
    }

    function testCannotProposeIfLastProposalIsActive(uint256 votes) public {
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

        ProposalAction[] memory firstProposalActions = new ProposalAction[](1);
        firstProposalActions[0] = testAction;
    
        // setup first proposal
        hoax(grantProposer);
        uint256 proposalId = serpentor.propose(firstProposalActions, "send grant to contributor");
        // increase block.number after startBlock
        vm.roll(serpentor.votingDelay() + 2);
        uint8 state = serpentor.ordinalState(proposalId);
        assertEq(state,uint8(ProposalState.ACTIVE));
        ProposalAction[] memory secondProposalActions = new ProposalAction[](1);
        secondProposalActions[0] = testAction;

        // execute
        vm.expectRevert(bytes("!latestPropId_state"));
        hoax(grantProposer);
        serpentor.propose(secondProposalActions, "send second grant to contributor");
    }

    function testShouldCancelWhenSenderIsProposerAndProposalActive(uint256 votes) public {
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

        ProposalAction[] memory proposalActions = new ProposalAction[](1);
        proposalActions[0] = testAction;
    
        // setup proposal
        hoax(grantProposer);
        uint256 proposalId = serpentor.propose(proposalActions, "send grant to contributor");
        console.log("proposalId", proposalId);
        // increase block.number after startBlock
        vm.roll(serpentor.votingDelay() + 2);
        uint8 state = serpentor.ordinalState(proposalId);
        assertEq(state,uint8(ProposalState.ACTIVE));
        // setup event
        vm.expectEmit(false, false, false, false);
        emit ProposalCanceled(proposalId);

        // execute
        hoax(grantProposer);
        serpentor.cancel(proposalId);
        state = serpentor.ordinalState(proposalId);
        Proposal memory updatedProposal = serpentor.proposals(proposalId);

        // asserts
        assertTrue(updatedProposal.canceled);
        assertEq(state,uint8(ProposalState.CANCELED));
    }

    function testShouldCancelProposalIfProposerIsBelowThreshold(
        uint256 votes,
        uint256 updatedVotes
    ) public {
            uint256 threshold = serpentor.proposalThreshold();
        // if maxActions is a big number, tests runs out of gas
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(updatedVotes < threshold);
        // setup
        address grantProposer = address(0xBEEF);
        address randomAcct = address(0xdeadbeef);
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

        ProposalAction[] memory proposalActions = new ProposalAction[](1);
        proposalActions[0] = testAction;
    
        // setup proposal
        hoax(grantProposer);
        uint256 proposalId = serpentor.propose(proposalActions, "send grant to contributor");
        // increase block.number after startBlock
        vm.roll(serpentor.votingDelay() + 2);
        uint8 state = serpentor.ordinalState(proposalId);
        assertEq(state,uint8(ProposalState.ACTIVE));
        // proposer goes below
        uint256 balanceOut = votes - updatedVotes;
        hoax(grantProposer);
        token.transfer(address(100), balanceOut);
        assertEq(token.balanceOf(grantProposer), updatedVotes);
        // setup event
        vm.expectEmit(false, false, false, false);
        emit ProposalCanceled(proposalId);
    
        // execute
        hoax(randomAcct);
        serpentor.cancel(proposalId);
        state = serpentor.ordinalState(proposalId);
        Proposal memory updatedProposal = serpentor.proposals(proposalId);

        // asserts
        assertTrue(updatedProposal.canceled);
        assertEq(state,uint8(ProposalState.CANCELED));
    }
    // TODO: add whitelisted
    function testCannotCancelWhitelistedProposerBelowThreshold(
        uint256 votes,
        uint256 updatedVotes
    ) public {
        uint256 threshold = serpentor.proposalThreshold();
        // if maxActions is a big number, tests runs out of gas
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(updatedVotes < threshold);
        // setup
        address grantProposer = address(0xBEEF);
        address randomAcct = address(0xdeadbeef);
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

        ProposalAction[] memory proposalActions = new ProposalAction[](1);
        proposalActions[0] = testAction;
    
        // setup proposal
        hoax(grantProposer);
        uint256 proposalId = serpentor.propose(proposalActions, "send grant to contributor");
        // increase block.number after startBlock
        vm.roll(serpentor.votingDelay() + 2);
        uint8 state = serpentor.ordinalState(proposalId);
        assertEq(state,uint8(ProposalState.ACTIVE));
        // proposer goes below
        uint256 balanceOut = votes - updatedVotes;
        hoax(grantProposer);
        token.transfer(address(100), balanceOut);
        assertEq(token.balanceOf(grantProposer), updatedVotes);
        // setup event
        vm.expectEmit(false, false, false, false);
        emit ProposalCanceled(proposalId);
    
        // execute
        hoax(randomAcct);
        serpentor.cancel(proposalId);
        state = serpentor.ordinalState(proposalId);
        Proposal memory updatedProposal = serpentor.proposals(proposalId);

        // asserts
        assertTrue(updatedProposal.canceled);
        assertEq(state,uint8(ProposalState.CANCELED));
    }

    function testSetWhitelistedAccountAsQueen(address randomAcct, uint256 expiration) public {
        // setup
        vm.assume(randomAcct != knight && randomAcct != address(timelock) && randomAcct != whitelistedProposer);
        vm.assume(expiration > block.timestamp + 10 days && expiration < type(uint128).max);
        
        // execute
        hoax(address(timelock));
        serpentor.setWhitelistAccountExpiration(randomAcct, expiration);

        // assert
        assertTrue(serpentor.isWhitelisted(randomAcct));
    }

    function testSetWhitelistedAccountAsKnight(address randomAcct, uint256 expiration) public {
        // setup
        vm.assume(randomAcct != knight && randomAcct != address(timelock) && randomAcct != whitelistedProposer);
        vm.assume(expiration > block.timestamp + 10 days && expiration < type(uint128).max);
        
        // execute
        hoax(address(knight));
        serpentor.setWhitelistAccountExpiration(randomAcct, expiration);

        // assert
        assertTrue(serpentor.isWhitelisted(randomAcct));
    }

    function testCannotSetWhitelistedAccount(address randomAcct, uint256 expiration) public {
        // setup
        vm.assume(randomAcct != knight && randomAcct != address(timelock));
        vm.assume(expiration > block.timestamp + 10 days && expiration < type(uint128).max);
        
        // execute
        vm.expectRevert(bytes("!access"));
        hoax(address(randomAcct));
        serpentor.setWhitelistAccountExpiration(randomAcct, expiration);
    }
}
