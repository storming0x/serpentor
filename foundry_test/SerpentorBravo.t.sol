// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/IERC20.sol";
import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {
    SerpentorBravo, 
    ProposalAction, 
    Proposal, 
    ProposalState,
    Receipt
} from "./interfaces/SerpentorBravo.sol";
import {Timelock} from "./interfaces/Timelock.sol";
import {GovToken} from "./utils/GovToken.sol";

contract SerpentorBravoTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    SerpentorBravo private serpentor;

    Timelock private timelock;
    GovToken private token;
    uint8 public constant ARR_SIZE = 7;
    uint public constant GRACE_PERIOD = 14 days;
    uint public constant MINIMUM_DELAY = 1;
    uint public constant MAXIMUM_DELAY = 40320;
    uint public constant MIN_VOTING_PERIOD = 5760; // about 24 hours
    uint public constant MAX_VOTING_PERIOD = 80640; // 2 weeks

    uint public constant MIN_PROPOSAL_THRESHOLD = 100e18; 
    uint public constant MAX_PROPOSAL_THRESHOLD = 5000e18; // 2 weeks

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
    address public grantee = address(0xABCD);

    mapping(address => bool) public reserved;
    mapping(address => bool) public isVoter; // for tracking duplicates in fuzzing

    address[] reservedList;

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

    event ProposalQueued(uint256 id, uint256 eta);

    event VoteCast(
        address indexed voter, 
        uint256 proposalId,
        uint8 support,
        uint256 votes,
        string reason
    );

    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresoldSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);

    event NewQueen(address indexed oldQueen, address indexed newQueen);
    event NewKnight(address indexed oldKnight, address indexed newKnight);    

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
        vm.label(whitelistedProposer, "whitelistedProposer");
        vm.label(grantee, "grantee");

        setupReservedAddress();

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
        vm.assume(votes > threshold && votes < type(uint128).max);
        // setup
        address grantProposer = address(0xBEEF);
        ProposalAction[] memory actions = setupTestProposal(grantProposer, votes);
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
        vm.assume(votes > threshold && votes < type(uint128).max);
         
        // setup first proposal
        address grantProposer = address(0xBEEF);
        ProposalAction[] memory firstProposalActions = setupTestProposal(grantProposer, votes);
        hoax(grantProposer);
        uint256 proposalId = serpentor.propose(firstProposalActions, "send grant to contributor");
        uint8 state = serpentor.ordinalState(proposalId);
        assertTrue(state == uint8(ProposalState.PENDING));

        ProposalAction[] memory secondProposalActions = new ProposalAction[](1);
        // copy action
        secondProposalActions[0] = firstProposalActions[0];

        // execute
        vm.expectRevert(bytes("!latestPropId_state"));
        hoax(grantProposer);
        serpentor.propose(secondProposalActions, "send second grant to contributor");
    }

    function testCannotProposeIfLastProposalIsActive(uint256 votes) public {
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > threshold && votes < type(uint128).max);
          
        // setup first proposal
        address grantProposer = address(0xBEEF);
        ProposalAction[] memory firstProposalActions = setupTestProposal(grantProposer, votes);
        hoax(grantProposer);
        uint256 proposalId = serpentor.propose(firstProposalActions, "send grant to contributor");
        // increase block.number after startBlock
        vm.roll(serpentor.votingDelay() + 2);
        uint8 state = serpentor.ordinalState(proposalId);
        assertEq(state,uint8(ProposalState.ACTIVE));
        ProposalAction[] memory secondProposalActions = new ProposalAction[](1);
        secondProposalActions[0] = firstProposalActions[0];

        // execute
        vm.expectRevert(bytes("!latestPropId_state"));
        hoax(grantProposer);
        serpentor.propose(secondProposalActions, "send second grant to contributor");
    }

    function testShouldCancelWhenSenderIsProposerAndProposalActive(uint256 votes, address grantProposer) public {
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(isNotReservedAddress(grantProposer));
        vm.assume(votes > threshold && votes < type(uint128).max);
        // setup proposal
        ProposalAction[] memory proposalActions = setupTestProposal(grantProposer, votes);
        hoax(grantProposer);
        uint256 proposalId = serpentor.propose(proposalActions, "send grant to contributor");
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

    function testCannotCancelProposalIfProposerIsAboveThreshold(
        uint256 votes,
        address grantProposer,
        address randomAcct
    ) public {
        vm.assume(randomAcct != grantProposer);
        vm.assume(isNotReservedAddress(randomAcct));
        vm.assume(isNotReservedAddress(grantProposer));
        uint256 threshold = serpentor.proposalThreshold();
        // if maxActions is a big number, tests runs out of gas
        vm.assume(votes > threshold && votes < type(uint128).max);
        // setup proposal
 
        ProposalAction[] memory proposalActions = setupTestProposal(grantProposer, votes);
    
        hoax(grantProposer);
        uint256 proposalId = serpentor.propose(proposalActions, "send grant to contributor");
        // increase block.number after startBlock
        vm.roll(serpentor.votingDelay() + 2);
        uint8 state = serpentor.ordinalState(proposalId);
        assertEq(state,uint8(ProposalState.ACTIVE));
        // setup event
        vm.expectRevert(bytes("!threshold"));
    
        // execute
        hoax(randomAcct);
        serpentor.cancel(proposalId);
    }

    function testShouldCancelProposalIfProposerIsBelowThreshold(
        uint256 votes,
        uint256 updatedVotes,
        address grantProposer,
        address randomAcct
    ) public {
        vm.assume(isNotReservedAddress(randomAcct));
        vm.assume(isNotReservedAddress(grantProposer));
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(updatedVotes < threshold);
        // setup proposal
        ProposalAction[] memory proposalActions = setupTestProposal(grantProposer, votes);
        uint256 proposalId = submitActiveTestProposal(proposalActions, grantProposer);

        // proposer goes below
        uint256 balanceOut = votes - updatedVotes;
        hoax(grantProposer);
        // burn balance
        token.transfer(address(token), balanceOut);
        assertEq(token.balanceOf(grantProposer), updatedVotes);
        // setup event
        vm.expectEmit(false, false, false, false);
        emit ProposalCanceled(proposalId);
    
        // execute
        hoax(randomAcct);
        serpentor.cancel(proposalId);
        uint256 state = serpentor.ordinalState(proposalId);
        Proposal memory updatedProposal = serpentor.proposals(proposalId);

        // asserts
        assertTrue(updatedProposal.canceled);
        assertEq(state,uint8(ProposalState.CANCELED));
    }

    function testShouldCancelQueuedProposal(
        address[ARR_SIZE] memory voters
    ) public {
        // setup
        vm.assume(noReservedAddress(voters));
        vm.assume(noDuplicates(voters));
        address grantProposer = address(0xBEEF);
        address random = address(0xdeadbeef);

        uint256 threshold = serpentor.proposalThreshold();
        // setup proposal
        uint256 expectedETA;
        uint256 proposalId;
        ProposalAction[] memory proposalActions = setupTestProposal(grantProposer, threshold + 1);
        (proposalId, expectedETA) = submitQueuedTestProposal(voters, proposalActions, grantProposer);
        Proposal memory proposal = serpentor.proposals(proposalId);
        bytes32 expectedTxHash = _getTrxHash(proposal.actions[0], expectedETA);

        console.log("proposalQueued");
        // proposer goes below
        uint256 balanceOut = token.balanceOf(grantProposer) - threshold;
        hoax(grantProposer);
        // burn balance
        token.transfer(address(token), threshold);
        assertEq(token.balanceOf(grantProposer), balanceOut);

        // execute
        hoax(random);
        serpentor.cancel(proposalId);

        // asserts
        assertEq(serpentor.ordinalState(proposalId), uint8(ProposalState.CANCELED));
        assertFalse(timelock.queuedTransactions(expectedTxHash));
    }

    function testCannotCancelWhitelistedProposerBelowThreshold(
        uint256 votes,
        uint256 updatedVotes,
        address randomAcct
    ) public {
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(updatedVotes < threshold);
        vm.assume(isNotReservedAddress(randomAcct));
        // setup
        ProposalAction[] memory proposalActions = setupTestProposal(whitelistedProposer, votes);
        uint256 proposalId = submitActiveTestProposal(proposalActions, whitelistedProposer);

        // proposer goes below
        uint256 balanceOut = votes - updatedVotes;
        hoax(whitelistedProposer);
        // burn balance
        token.transfer(address(token), balanceOut);
        assertEq(token.balanceOf(whitelistedProposer), updatedVotes);
        // setup revert
        vm.expectRevert(bytes("!whitelisted_proposer"));
    
        // execute
        hoax(randomAcct);
        serpentor.cancel(proposalId);
    }

    function testShouldCancelWhitelistedProposerBelowThresholdAsKnight(
        uint256 votes,
        uint256 updatedVotes
    ) public {
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(updatedVotes < threshold);
        // setup
        ProposalAction[] memory proposalActions = setupTestProposal(whitelistedProposer, votes);
        uint256 proposalId = submitActiveTestProposal(proposalActions, whitelistedProposer);

        // proposer goes below
        uint256 balanceOut = votes - updatedVotes;
        hoax(whitelistedProposer);
        // burn balance
        token.transfer(address(token), balanceOut);
        assertEq(token.balanceOf(whitelistedProposer), updatedVotes);
        // setup event
        vm.expectEmit(false, false, false, false);
        emit ProposalCanceled(proposalId);
    
        // execute
        hoax(knight);
        serpentor.cancel(proposalId);

        uint256 state = serpentor.ordinalState(proposalId);
        Proposal memory updatedProposal = serpentor.proposals(proposalId);

        // asserts
        assertTrue(updatedProposal.canceled);
        assertEq(state,uint8(ProposalState.CANCELED));
    }

    function testSetWhitelistedAccountAsQueen(address randomAcct, uint256 expiration) public {
        // setup
        vm.assume(isNotReservedAddress(randomAcct));
        vm.assume(expiration > block.timestamp + 10 days && expiration < type(uint128).max);
        
        // execute
        hoax(address(timelock));
        serpentor.setWhitelistAccountExpiration(randomAcct, expiration);

        // assert
        assertTrue(serpentor.isWhitelisted(randomAcct));
    }

    function testSetWhitelistedAccountAsKnight(address randomAcct, uint256 expiration) public {
        // setup
        vm.assume(isNotReservedAddress(randomAcct));
        vm.assume(expiration > block.timestamp + 10 days && expiration < type(uint128).max);
        
        // execute
        hoax(address(knight));
        serpentor.setWhitelistAccountExpiration(randomAcct, expiration);

        // assert
        assertTrue(serpentor.isWhitelisted(randomAcct));
    }

    function testCannotSetWhitelistedAccount(address randomAcct, uint256 expiration) public {
        // setup
        vm.assume(isNotReservedAddress(randomAcct));
        vm.assume(expiration > block.timestamp + 10 days && expiration < type(uint128).max);
        
        // execute
        vm.expectRevert(bytes("!access"));
        hoax(address(randomAcct));
        serpentor.setWhitelistAccountExpiration(randomAcct, expiration);
    }

    function testCannotVoteWithInvalidOption(uint256 votes, address voter, uint8 support) public {
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(isNotReservedAddress(voter));
        vm.assume(support > 2);
        // setup
        ProposalAction[] memory proposalActions = setupTestProposal(whitelistedProposer, votes);
        uint256 proposalId = submitActiveTestProposal(proposalActions, whitelistedProposer);
        vm.expectRevert(bytes("!vote_type"));

        // execute
        hoax(voter);
        serpentor.vote(proposalId, support); // invalid
    }

     function testCannotVoteMoreThanOnce(uint256 votes, address voter, uint8 support) public {
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(isNotReservedAddress(voter));
        vm.assume(support <= 2);
        // setup
        ProposalAction[] memory proposalActions = setupTestProposal(whitelistedProposer, votes);
        uint256 proposalId = submitActiveTestProposal(proposalActions, whitelistedProposer);
        // vote first time
        hoax(voter);
        serpentor.vote(proposalId, support); 
        vm.expectRevert(bytes("!hasVoted"));

        // execute
        hoax(voter);
        serpentor.vote(proposalId, support); 
    }

    function testCannotVoteOnInactiveProposal(uint256 votes, address voter, uint8 support) public {
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(isNotReservedAddress(voter));
        vm.assume(support <= 2);
        // setup
        ProposalAction[] memory proposalActions = setupTestProposal(whitelistedProposer, votes);
        uint256 proposalId = submitPendingTestProposal(proposalActions, whitelistedProposer);
        vm.expectRevert(bytes("!active"));
        
        // execute
        hoax(voter);
        serpentor.vote(proposalId, support); 
    }

    function testShouldVoteCorrectly(
        uint256 votes, 
        address voter, 
        uint8 support
    ) public {
        // setup
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > 1000000 && votes < type(uint256).max);
        vm.assume(isNotReservedAddress(voter));
        vm.assume(support <= 2);
      
        // setup voter votes
        deal(address(token), voter, votes);

        ProposalAction[] memory proposalActions = setupTestProposal(whitelistedProposer, threshold + 1);
        uint256 proposalId = submitActiveTestProposal(proposalActions, whitelistedProposer);
        
        // setup event
        vm.expectEmit(true, false, false, false);
        emit VoteCast(voter, proposalId, support, votes, "");

        // execute
        hoax(voter);
        serpentor.vote(proposalId, support); 
        Proposal memory proposal = serpentor.proposals(proposalId);
        Receipt memory receipt = serpentor.getReceipt(proposalId, voter);

        // asserts
        assertTrue(receipt.hasVoted);
        assertEq(receipt.support, support);
        assertEq(receipt.votes, votes);
        assertVotes(proposal, votes, support);
    }

    function testShouldVoteWithReasonCorrectly(
        uint256 votes, 
        address voter, 
        uint8 support
    ) public {
        // setup
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > 1000000 && votes < type(uint256).max);
        vm.assume(isNotReservedAddress(voter));
        vm.assume(support <= 2);
      
        // setup voter votes
        deal(address(token), voter, votes);

        ProposalAction[] memory proposalActions = setupTestProposal(whitelistedProposer, threshold + 1);
        uint256 proposalId = submitActiveTestProposal(proposalActions, whitelistedProposer);
        
        // setup event
        vm.expectEmit(true, false, false, false);
        emit VoteCast(voter, proposalId, support, votes, "test");

        // execute
        hoax(voter);
        serpentor.voteWithReason(proposalId, support, "test"); 
        Proposal memory proposal = serpentor.proposals(proposalId);
        Receipt memory receipt = serpentor.getReceipt(proposalId, voter);

        // asserts
        assertTrue(receipt.hasVoted);
        assertEq(receipt.support, support);
        assertEq(receipt.votes, votes);
        assertVotes(proposal, votes, support);
    }

    function testCannotQueueProposalIfNotSucceeded() public {
        // setup
        uint256 threshold = serpentor.proposalThreshold();
        ProposalAction[] memory proposalActions = setupTestProposal(whitelistedProposer, threshold + 1);
        uint256 proposalId = submitActiveTestProposal(proposalActions, whitelistedProposer);
        // proposal still active cant be queued
        vm.expectRevert(bytes("!succeeded"));

        // execute
        hoax(smallVoter);
        serpentor.queue(proposalId); 
    }

    function testShouldQueueProposal(
        address[ARR_SIZE] memory voters
    ) public {
        // setup
        vm.assume(noReservedAddress(voters));
        vm.assume(noDuplicates(voters));
        uint256 threshold = serpentor.proposalThreshold();
        uint256 expectedETA;
        uint256 proposalId;
        ProposalAction[] memory proposalActions = setupTestProposal(whitelistedProposer, threshold + 1);
       
        // execute
        (proposalId, expectedETA) = submitQueuedTestProposal(voters, proposalActions, whitelistedProposer);

        Proposal memory proposal = serpentor.proposals(proposalId);
        bytes32 expectedTxHash = _getTrxHash(proposal.actions[0], expectedETA);

        // asserts
        assertEq(serpentor.ordinalState(proposalId), uint8(ProposalState.QUEUED));
        assertEq(proposal.eta, expectedETA);
        assertTrue(timelock.queuedTransactions(expectedTxHash));
    }

    function testGetAction() public {
        // setup
        uint256 threshold = serpentor.proposalThreshold();
        ProposalAction[] memory expectedActions = setupTestProposal(whitelistedProposer, threshold + 1);
        uint256 proposalId = submitActiveTestProposal(expectedActions, whitelistedProposer);

        // execute
        ProposalAction[] memory actions = serpentor.getActions(proposalId);

        // asserts
        assertEq(actions.length, expectedActions.length);
        assertEq(actions[0].target, expectedActions[0].target);
        assertEq(actions[0].amount, expectedActions[0].amount);
        assertEq(actions[0].signature, expectedActions[0].signature);
        assertEq(actions[0].callData, expectedActions[0].callData);
    }

    function testRandomAcctCannotSetVotingPeriod(address random, uint256 newVotingPeriod) public {
        vm.assume(isNotReservedAddress(random));
        vm.assume(newVotingPeriod >= MIN_VOTING_PERIOD && newVotingPeriod <= MAX_VOTING_PERIOD);
        // setup
        vm.expectRevert(bytes("!queen"));
        // execute
        vm.prank(random);
        serpentor.setVotingPeriod(newVotingPeriod);
    }

    function testCannotSetVotingPeriodOutsideRange(address random, uint32 newVotingPeriod) public {
        vm.assume(isNotReservedAddress(random));
        vm.assume(newVotingPeriod == 0 || newVotingPeriod == 1 || newVotingPeriod > MAX_VOTING_PERIOD);
        address currentQueen = serpentor.queen();
        // setup
        vm.expectRevert(bytes("!votingPeriod"));
        // execute
        hoax(currentQueen);
        serpentor.setVotingPeriod(newVotingPeriod);
    }

    function testShouldSetVotingPeriod(address random, uint256 newVotingPeriod) public {
        vm.assume(isNotReservedAddress(random));
        vm.assume(newVotingPeriod >= MIN_VOTING_PERIOD && newVotingPeriod <= MAX_VOTING_PERIOD);
        // setup
        address currentQueen = serpentor.queen();
        uint256 oldVotingPeriod = serpentor.votingPeriod();
        // setup event
        vm.expectEmit(false, false, false, false);
        emit VotingPeriodSet(oldVotingPeriod, newVotingPeriod);
        // execute
        vm.prank(currentQueen);
        serpentor.setVotingPeriod(newVotingPeriod);

        // asserts
        assertEq(serpentor.votingPeriod(), newVotingPeriod);
    }

    function testRandomAcctCannotSetProposalThreshold(address random, uint256 newProposalThreshold) public {
        vm.assume(isNotReservedAddress(random));
        vm.assume(newProposalThreshold >= MIN_PROPOSAL_THRESHOLD && newProposalThreshold <= MAX_PROPOSAL_THRESHOLD);
        // setup
        vm.expectRevert(bytes("!queen"));
        // execute
        hoax(random);
        serpentor.setProposalThreshold(newProposalThreshold);
    }

    function testCannotSetProposalThresholdOutsideRange(uint32 newProposalThreshold) public {
        vm.assume(newProposalThreshold == 0 || newProposalThreshold == 1 || newProposalThreshold > MAX_PROPOSAL_THRESHOLD);
        address currentQueen = serpentor.queen();
        // setup
        vm.expectRevert(bytes("!threshold"));
        // execute
        hoax(currentQueen);
        serpentor.setProposalThreshold(newProposalThreshold);
    }

    function testShouldSetProposalThreshold(uint256 newProposalThreshold) public {
        vm.assume(newProposalThreshold >= MIN_PROPOSAL_THRESHOLD && newProposalThreshold <= MAX_PROPOSAL_THRESHOLD);
        // setup
        address currentQueen = serpentor.queen();
        uint256 oldProposalThreshold = serpentor.proposalThreshold();
        // setup event
        vm.expectEmit(false, false, false, false);
        emit ProposalThresoldSet(oldProposalThreshold, newProposalThreshold);
        // execute
        vm.prank(currentQueen);
        serpentor.setProposalThreshold(newProposalThreshold);

        // asserts
        assertEq(serpentor.proposalThreshold(), newProposalThreshold);
    }

    function testRandomAcctCannotSetNewQueen(address random) public {
        vm.assume(isNotReservedAddress(random));
        // setup
        vm.expectRevert(bytes("!queen"));
        // execute
        vm.prank(random);
        serpentor.setPendingQueen(random);
    }

    function testRandomAcctCannotTakeOverThrone(address random) public {
       vm.assume(isNotReservedAddress(random));
        // setup
        vm.expectRevert(bytes("!pendingQueen"));
        // execute
        vm.prank(random);
        serpentor.acceptThrone();
    }

    function testOnlyPendingQueenCanAcceptThrone(address futureQueen) public {
        // setup
        vm.assume(isNotReservedAddress(futureQueen));
        address oldQueen = serpentor.queen();
        // setup pendingQueen
        vm.prank(address(timelock));
        serpentor.setPendingQueen(futureQueen);
        assertEq(serpentor.pendingQueen(), futureQueen);
        //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit NewQueen(oldQueen, futureQueen);

        // execute
        vm.prank(futureQueen);
        serpentor.acceptThrone();

        // asserts
        assertEq(serpentor.queen(), futureQueen);
        assertEq(serpentor.pendingQueen(), address(0));
    } 

    function testRandomAcctCannotSetNewKnight(address random) public {
        vm.assume(isNotReservedAddress(random));
        // setup
        vm.expectRevert(bytes("!queen"));
        // execute
        vm.prank(random);
        serpentor.setKnight(random);
    }

    function testSetNewKnight(address newKnight) public {
        vm.assume(isNotReservedAddress(newKnight));
        address currentQueen = serpentor.queen();
        address oldKnight = serpentor.knight();

        //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit NewKnight(oldKnight, newKnight);

        // execute
        vm.prank(currentQueen);
        serpentor.setKnight(newKnight);
    }

    function testCannotSetVotingDelayOutsideRange(address random, uint32 newVotingDelay) public {
        vm.assume(isNotReservedAddress(random));
        vm.assume(newVotingDelay == 0 || newVotingDelay > MAXIMUM_DELAY);
        // setup
        address currentQueen = serpentor.queen();
        vm.expectRevert(bytes("!votingDelay"));
        // execute
        vm.prank(currentQueen);
        serpentor.setVotingDelay(newVotingDelay);
    }

    function testRandomAcctCannotSetVotingDelay(address random, uint256 newVotingDelay) public {
        vm.assume(isNotReservedAddress(random));
        vm.assume(newVotingDelay >= MINIMUM_DELAY && newVotingDelay <= MAXIMUM_DELAY);
        // setup
        vm.expectRevert(bytes("!queen"));
        // execute
        vm.prank(random);
        serpentor.setVotingDelay(newVotingDelay);
    }

     function testShouldSetVotingDelay(address random, uint256 newVotingDelay) public {
        vm.assume(isNotReservedAddress(random));
        vm.assume(newVotingDelay >= MINIMUM_DELAY && newVotingDelay <= MAXIMUM_DELAY);
        // setup
        address currentQueen = serpentor.queen();
        uint256 oldVotingDelay = serpentor.votingDelay();
        // setup event
        vm.expectEmit(false, false, false, false);
        emit VotingDelaySet(oldVotingDelay, newVotingDelay);
        // execute
        vm.prank(currentQueen);
        serpentor.setVotingDelay(newVotingDelay);

        // asserts
        assertEq(serpentor.votingDelay(), newVotingDelay);
    }

    // helper methods

    function setupVotingBalancesToPass(address[ARR_SIZE] memory voters) internal returns (uint256[ARR_SIZE] memory) {
        uint quorum = serpentor.quorumVotes();
        uint[ARR_SIZE] memory votes;
        for (uint i = 0; i < voters.length; i++) {
            votes[i] = (quorum / ARR_SIZE) +  29;
        }
        // deal balances to voters
        for (uint i = 0; i < voters.length; i++) {
            deal(address(token), voters[i], votes[i]);
        }

        return votes;
    }
    // NOTE: cant overflow since array is set from quorum division
    function countVotes(uint256[ARR_SIZE] memory votes) internal returns (uint256) {
        uint256 total;
        for (uint i = 0; i < votes.length; i++) {
           total += votes[i];
        }

        return total;
    }

    function noZeroVotes(uint8[ARR_SIZE] memory votes) internal returns (bool) {
        for (uint i = 0; i < votes.length; i++) {
           if (votes[i] == 0) {
             return false;
           }
        }

        return true;
    }


    function setupTestProposal(
        address grantProposer, 
        uint256 votes
    ) internal returns (ProposalAction[] memory) {

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

        return actions;
    }

    function submitQueuedTestProposal(
        address[ARR_SIZE] memory voters,
        ProposalAction[] memory proposalActions, 
        address _proposer
    ) internal returns (uint256 proposalId , uint256 expectedETA) {
        uint256[ARR_SIZE] memory votes = setupVotingBalancesToPass(voters);
        skip(1 days);
       
        uint256 voteCount = countVotes(votes);
        assertTrue(voteCount > serpentor.quorumVotes());
    
        proposalId = submitActiveTestProposal(proposalActions, _proposer);

        // execute voting
        for (uint i = 0; i < voters.length; i++) {
            hoax(voters[i]);
            serpentor.vote(proposalId, 1); // for
        }
        Proposal memory proposal = serpentor.proposals(proposalId);
        vm.roll(proposal.endBlock + 2);
        
        assertEq(serpentor.ordinalState(proposalId), uint8(ProposalState.SUCCEEDED));
        expectedETA = block.timestamp + timelock.delay();

        //setup event
        vm.expectEmit(false, false, false, false);
        emit ProposalQueued(proposalId, expectedETA);

        // execute
        hoax(smallVoter);
        serpentor.queue(proposalId); 
    }

    function submitActiveTestProposal(
        ProposalAction[] memory proposalActions, 
        address _proposer
    ) 
        internal returns (uint256) {
        // submit proposal
        hoax(_proposer);
        uint256 proposalId = serpentor.propose(proposalActions, "send grant to contributor");
        // increase block.number after startBlock
        vm.roll(serpentor.votingDelay() + 2);
        uint8 state = serpentor.ordinalState(proposalId);
        assertEq(state,uint8(ProposalState.ACTIVE));

        return proposalId;
    }

     function submitPendingTestProposal(
        ProposalAction[] memory proposalActions, 
        address _proposer
    ) 
        internal returns (uint256) {
        // submit proposal
        hoax(_proposer);
        uint256 proposalId = serpentor.propose(proposalActions, "send grant to contributor");
        // increase block.number after startBlock
        uint8 state = serpentor.ordinalState(proposalId);
        assertEq(state,uint8(ProposalState.PENDING));

        return proposalId;
    }

    function setupReservedAddress() internal {
        reservedList = [
            queen, 
            proposer,
            smallVoter, 
            mediumVoter, 
            whaleVoter1, 
            whaleVoter2, 
            whitelistedProposer,
            knight,
            grantee,
            address(0),
            address(timelock),
            address(serpentor),
            address(token)
        ];
        for (uint i = 0; i < reservedList.length; i++)
             reserved[reservedList[i]] = true;
    }

    function assertVotes(Proposal memory proposal, uint256 votes, uint8 support) internal {
        if (support == 0) {
            assertEq(proposal.againstVotes, votes);
        }
        if (support == 1) {
            assertEq(proposal.forVotes, votes);
        }

        if (support == 2) {
            assertEq(proposal.abstainVotes, votes);
        }

    }

    function isNotReservedAddress(address account) internal view returns (bool) {
        return !reserved[account];
    }

    function noReservedAddress(address[ARR_SIZE] memory accounts) internal view returns (bool) {
        for (uint i = 0; i < accounts.length; i++)
             if (reserved[accounts[i]]) {
                return false;
             }
        return true;
    }

    function noDuplicates(address[ARR_SIZE] memory accounts) internal returns (bool) {
        for (uint i = 0; i < accounts.length; i++) {
             if (isVoter[accounts[i]]) {
                return false;
             }
             isVoter[accounts[i]] = true;
        }
             
        return true;
    }

    function _getTrxHash(
        ProposalAction memory action,
        uint eta
    ) internal pure returns (bytes32) {
        bytes32 trxHash = keccak256(abi.encode(
            action.target, 
            action.amount, 
            action.signature, 
            action.callData, 
            eta
        ));

        return trxHash;
    }
}
