// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/IERC20.sol";
import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";
import {SigUtils} from "./utils/SigUtils.sol";

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
    SigUtils private sigUtils;

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
    uint256 public constant transferAmount = 1e18;
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

    address[] public reservedList;

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
    event ProposalExecuted(uint256 proposalId);

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

        sigUtils = new SigUtils(serpentor.domainSeparator());

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

        _setupReservedAddress();

        // setup coupled governance between serpentor and timelock
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

    function testShouldComputeDomainSeparatorCorrectly() public {
        // setup
        bytes32 expectedDomainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(abi.encodePacked(serpentor.name())),
            keccak256("1"),
            block.chainid,
            address(serpentor)
        ));

        bytes32 domainSeparator = serpentor.domainSeparator();

        assertEq(domainSeparator, expectedDomainSeparator);

    }

    function testCannotProposeTooManyActions(uint256 votes, uint8 size) public {
        uint256 maxActions = serpentor.proposalMaxActions();
        uint256 threshold = serpentor.proposalThreshold();
        // if maxActions is a big number, tests runs out of gas
        vm.assume(votes > threshold && size >= maxActions && size <= maxActions + 5);
        // setup
        address yoloProposer = address(0xBEEF);
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
        ProposalAction[] memory actions = _setupTestProposal(grantProposer, votes);
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
        ProposalAction[] memory firstProposalActions = _setupTestProposal(grantProposer, votes);
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
        ProposalAction[] memory firstProposalActions = _setupTestProposal(grantProposer, votes);
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
        vm.assume(_isNotReservedAddress(grantProposer));
        vm.assume(votes > threshold && votes < type(uint128).max);
        // setup proposal
        ProposalAction[] memory proposalActions = _setupTestProposal(grantProposer, votes);
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
        vm.assume(_isNotReservedAddress(randomAcct));
        vm.assume(_isNotReservedAddress(grantProposer));
        uint256 threshold = serpentor.proposalThreshold();
        // if maxActions is a big number, tests runs out of gas
        vm.assume(votes > threshold && votes < type(uint128).max);
        // setup proposal
 
        ProposalAction[] memory proposalActions = _setupTestProposal(grantProposer, votes);
    
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
        vm.assume(_isNotReservedAddress(randomAcct));
        vm.assume(_isNotReservedAddress(grantProposer));
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(updatedVotes < threshold);
        // setup proposal
        ProposalAction[] memory proposalActions = _setupTestProposal(grantProposer, votes);
        uint256 proposalId = _submitActiveTestProposal(proposalActions, grantProposer);

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
        vm.assume(_noReservedAddress(voters));
        vm.assume(_noDuplicates(voters));
        address grantProposer = proposer;
        address random = address(0xdeadbeef);

        uint256 threshold = serpentor.proposalThreshold();
        // setup proposal
        uint256 expectedETA;
        uint256 proposalId;
        ProposalAction[] memory proposalActions = _setupTestProposal(grantProposer, threshold + 1);
        (proposalId, expectedETA) = _submitQueuedTestProposal(voters, proposalActions, grantProposer);
        Proposal memory proposal = serpentor.proposals(proposalId);
        bytes32 expectedTxHash = _getTrxHash(proposal.actions[0], expectedETA);
        uint256 proposerBalance = token.balanceOf(grantProposer);
        // proposer goes below
        hoax(grantProposer);
        // burn balance
        token.transfer(address(token), proposerBalance);
        assertEq(token.balanceOf(grantProposer), 0);

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
        vm.assume(_isNotReservedAddress(randomAcct));
        // setup
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, votes);
        uint256 proposalId = _submitActiveTestProposal(proposalActions, whitelistedProposer);

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
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, votes);
        uint256 proposalId = _submitActiveTestProposal(proposalActions, whitelistedProposer);

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
        vm.assume(_isNotReservedAddress(randomAcct));
        vm.assume(expiration > block.timestamp + 10 days && expiration < type(uint128).max);
        
        // execute
        hoax(address(timelock));
        serpentor.setWhitelistAccountExpiration(randomAcct, expiration);

        // assert
        assertTrue(serpentor.isWhitelisted(randomAcct));
    }

    function testSetWhitelistedAccountAsKnight(address randomAcct, uint256 expiration) public {
        // setup
        vm.assume(_isNotReservedAddress(randomAcct));
        vm.assume(expiration > block.timestamp + 10 days && expiration < type(uint128).max);
        
        // execute
        hoax(address(knight));
        serpentor.setWhitelistAccountExpiration(randomAcct, expiration);

        // assert
        assertTrue(serpentor.isWhitelisted(randomAcct));
    }

    function testCannotSetWhitelistedAccount(address randomAcct, uint256 expiration) public {
        // setup
        vm.assume(_isNotReservedAddress(randomAcct));
        vm.assume(expiration > block.timestamp + 10 days && expiration < type(uint128).max);
        
        // execute
        vm.expectRevert(bytes("!access"));
        hoax(address(randomAcct));
        serpentor.setWhitelistAccountExpiration(randomAcct, expiration);
    }

    function testCannotVoteWithInvalidOption(uint256 votes, address voter, uint8 support) public {
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(_isNotReservedAddress(voter));
        vm.assume(support > 2);
        // setup
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, votes);
        uint256 proposalId = _submitActiveTestProposal(proposalActions, whitelistedProposer);
        vm.expectRevert(bytes("!vote_type"));

        // execute
        hoax(voter);
        serpentor.vote(proposalId, support); // invalid
    }

     function testCannotVoteMoreThanOnce(uint256 votes, address voter, uint8 support) public {
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > threshold && votes < type(uint128).max);
        vm.assume(_isNotReservedAddress(voter));
        vm.assume(support <= 2);
        // setup
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, votes);
        uint256 proposalId = _submitActiveTestProposal(proposalActions, whitelistedProposer);
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
        vm.assume(_isNotReservedAddress(voter));
        vm.assume(support <= 2);
        // setup
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, votes);
        uint256 proposalId = _submitPendingTestProposal(proposalActions, whitelistedProposer);
        vm.expectRevert(bytes("!active"));
        
        // execute
        hoax(voter);
        serpentor.vote(proposalId, support); 
    }

    function testShouldVote(
        uint256 votes, 
        address voter, 
        uint8 support
    ) public {
        // setup
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > 1000000 && votes < type(uint256).max);
        vm.assume(_isNotReservedAddress(voter));
        vm.assume(support <= 2);
      
        // setup voter votes
        deal(address(token), voter, votes);

        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, threshold + 1);
        uint256 proposalId = _submitActiveTestProposal(proposalActions, whitelistedProposer);
        
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
        _assertVotes(proposal, votes, support);
    }

    function testShouldVoteWithReason(
        uint256 votes, 
        address voter, 
        uint8 support
    ) public {
        // setup
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > 1000000 && votes < type(uint256).max);
        vm.assume(_isNotReservedAddress(voter));
        vm.assume(support <= 2);
      
        // setup voter votes
        deal(address(token), voter, votes);

        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, threshold + 1);
        uint256 proposalId = _submitActiveTestProposal(proposalActions, whitelistedProposer);
        
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
        _assertVotes(proposal, votes, support);
    }

    function testShouldVoteBySig(
        uint256 votes, 
        uint8 support,
        // private key needs to be lower than uint256 for secp256k1
        uint248 voterPrivateKey
    ) public {
        // setup
        uint256 threshold = serpentor.proposalThreshold();
        vm.assume(votes > 1000000 && votes < type(uint256).max);
        vm.assume(support <= 2);
        vm.assume(voterPrivateKey > 0);
        // generate voter from privateKey
        address voter = vm.addr(voterPrivateKey);
        vm.assume(_isNotReservedAddress(voter));
      
        // setup voter votes
        deal(address(token), voter, votes);

        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, threshold + 1);
        uint256 proposalId = _submitActiveTestProposal(proposalActions, whitelistedProposer);
        // create ballot
        SigUtils.Ballot memory ballot = SigUtils.Ballot({
            proposalId: proposalId,
            support: support
        });

        bytes32 digest = sigUtils.getTypedDataHash(ballot);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voterPrivateKey, digest);

        assertEq(token.balanceOf(address(0xdeadbeef)), 0);

        // setup event
        vm.expectEmit(true, false, false, false);
        emit VoteCast(voter, proposalId, support, votes, "");

        // execute
        hoax(address(0xdeadbeef)); // relayer
        serpentor.voteBySig(proposalId, support, v,r,s); 
        Proposal memory proposal = serpentor.proposals(proposalId);
        Receipt memory receipt = serpentor.getReceipt(proposalId, voter);

        // asserts
        assertTrue(receipt.hasVoted);
        assertEq(receipt.support, support);
        assertEq(receipt.votes, votes);
        _assertVotes(proposal, votes, support);
    }

    function testCannotQueueProposalIfNotSucceeded() public {
        // setup
        uint256 threshold = serpentor.proposalThreshold();
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, threshold + 1);
        uint256 proposalId = _submitActiveTestProposal(proposalActions, whitelistedProposer);
        // proposal still active cant be queued
        vm.expectRevert(bytes("!succeeded"));

        // execute
        hoax(smallVoter);
        serpentor.queue(proposalId); 
    }

    function testShouldHandleProposalDefeatedCorrectly(
        address[ARR_SIZE] memory voters
    ) public {
        // setup
        vm.assume(_noReservedAddress(voters));
        vm.assume(_noDuplicates(voters));
        uint256 threshold = serpentor.proposalThreshold();
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, threshold + 1);
       
        // execute
        uint256 proposalId = _submitDefeatedTestProposal(voters, proposalActions, whitelistedProposer);

        Proposal memory proposal = serpentor.proposals(proposalId);

        // asserts
        assertEq(serpentor.ordinalState(proposalId), uint8(ProposalState.DEFEATED));
        assertEq(proposal.eta, 0);
    }

    function testShouldQueueProposal(
        address[ARR_SIZE] memory voters
    ) public {
        // setup
        vm.assume(_noReservedAddress(voters));
        vm.assume(_noDuplicates(voters));
        uint256 threshold = serpentor.proposalThreshold();
        uint256 expectedETA;
        uint256 proposalId;
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, threshold + 1);
       
        // execute
        (proposalId, expectedETA) = _submitQueuedTestProposal(voters, proposalActions, whitelistedProposer);

        Proposal memory proposal = serpentor.proposals(proposalId);
        bytes32 expectedTxHash = _getTrxHash(proposal.actions[0], expectedETA);

        // asserts
        assertEq(serpentor.ordinalState(proposalId), uint8(ProposalState.QUEUED));
        assertEq(proposal.eta, expectedETA);
        assertTrue(timelock.queuedTransactions(expectedTxHash));
    }

    function testCannotExecuteProposalIfNotQueued() public {
        // setup
        uint256 threshold = serpentor.proposalThreshold();
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, threshold + 1);
       
        // setup active proposal
        uint256 proposalId =  _submitActiveTestProposal(proposalActions, whitelistedProposer);
        vm.expectRevert(bytes("!queued"));
        // execute
        hoax(smallVoter);
        serpentor.execute(proposalId);
    }

    function testShouldRevertExecutionIfTrxReverts(
        address[ARR_SIZE] memory voters
    ) public {
        // setup
        vm.assume(_noReservedAddress(voters));
        vm.assume(_noDuplicates(voters));
        uint256 threshold = serpentor.proposalThreshold();
        uint256 expectedETA;
        uint256 proposalId;
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, threshold + 1);
       
        // setup queued proposal
        (proposalId, expectedETA) = _submitQueuedTestProposal(voters, proposalActions, whitelistedProposer);

        Proposal memory proposal = serpentor.proposals(proposalId);
        bytes32 expectedTxHash = _getTrxHash(proposal.actions[0], expectedETA);
        
        skip(expectedETA + 1);
        // timelock does not have enough funds for proposal so trx will revert
        vm.expectRevert(bytes("!trx_revert"));
    
        // execute
        hoax(smallVoter);
        serpentor.execute(proposalId);

        // asserts
        assertTrue(timelock.queuedTransactions(expectedTxHash));
        assertEq(token.balanceOf(grantee), 0);
    }

    function testShouldExecuteQueuedProposal(
        address[ARR_SIZE] memory voters
    ) public {
        // setup
        vm.assume(_noReservedAddress(voters));
        vm.assume(_noDuplicates(voters));
        uint256 threshold = serpentor.proposalThreshold();
        uint256 expectedETA;
        uint256 proposalId;
        ProposalAction[] memory proposalActions = _setupTestProposal(whitelistedProposer, threshold + 1);
       
        // setup queued proposal
        (proposalId, expectedETA) = _submitQueuedTestProposal(voters, proposalActions, whitelistedProposer);

        Proposal memory proposal = serpentor.proposals(proposalId);
        bytes32 expectedTxHash = _getTrxHash(proposal.actions[0], expectedETA);
        // assert balance of grantee before proposal execution is none
        assertEq(token.balanceOf(grantee), 0);
        assertTrue(timelock.queuedTransactions(expectedTxHash));
        // timelock needs some funds to execute proposal for transfer of funds
        deal(address(token), address(timelock), 1000e18);
        skip(expectedETA + 1);
        // setup event
        vm.expectEmit(false, false, false, false);
        emit ProposalExecuted(proposalId);
    
        // execute
        hoax(smallVoter);
        serpentor.execute(proposalId);
        proposal = serpentor.proposals(proposalId);

        // asserts
        assertEq(serpentor.ordinalState(proposalId), uint8(ProposalState.EXECUTED));
        assertFalse(timelock.queuedTransactions(expectedTxHash));
        assertEq(token.balanceOf(grantee), transferAmount);
    }

    function testGetAction() public {
        // setup
        uint256 threshold = serpentor.proposalThreshold();
        ProposalAction[] memory expectedActions = _setupTestProposal(whitelistedProposer, threshold + 1);
        uint256 proposalId = _submitActiveTestProposal(expectedActions, whitelistedProposer);

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
        vm.assume(_isNotReservedAddress(random));
        vm.assume(newVotingPeriod >= MIN_VOTING_PERIOD && newVotingPeriod <= MAX_VOTING_PERIOD);
        // setup
        vm.expectRevert(bytes("!queen"));
        // execute
        vm.prank(random);
        serpentor.setVotingPeriod(newVotingPeriod);
    }

    function testCannotSetVotingPeriodOutsideRange(address random, uint32 newVotingPeriod) public {
        vm.assume(_isNotReservedAddress(random));
        vm.assume(newVotingPeriod == 0 || newVotingPeriod == 1 || newVotingPeriod > MAX_VOTING_PERIOD);
        address currentQueen = serpentor.queen();
        // setup
        vm.expectRevert(bytes("!votingPeriod"));
        // execute
        hoax(currentQueen);
        serpentor.setVotingPeriod(newVotingPeriod);
    }

    function testShouldSetVotingPeriod(address random, uint256 newVotingPeriod) public {
        vm.assume(_isNotReservedAddress(random));
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
        vm.assume(_isNotReservedAddress(random));
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
        vm.assume(_isNotReservedAddress(random));
        // setup
        vm.expectRevert(bytes("!queen"));
        // execute
        vm.prank(random);
        serpentor.setPendingQueen(random);
    }

    function testRandomAcctCannotTakeOverThrone(address random) public {
       vm.assume(_isNotReservedAddress(random));
        // setup
        vm.expectRevert(bytes("!pendingQueen"));
        // execute
        vm.prank(random);
        serpentor.acceptThrone();
    }

    function testOnlyPendingQueenCanAcceptThrone(address futureQueen) public {
        // setup
        vm.assume(_isNotReservedAddress(futureQueen));
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
        vm.assume(_isNotReservedAddress(random));
        // setup
        vm.expectRevert(bytes("!queen"));
        // execute
        vm.prank(random);
        serpentor.setKnight(random);
    }

    function testSetNewKnight(address newKnight) public {
        vm.assume(_isNotReservedAddress(newKnight));
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
        vm.assume(_isNotReservedAddress(random));
        vm.assume(newVotingDelay == 0 || newVotingDelay > MAXIMUM_DELAY);
        // setup
        address currentQueen = serpentor.queen();
        vm.expectRevert(bytes("!votingDelay"));
        // execute
        vm.prank(currentQueen);
        serpentor.setVotingDelay(newVotingDelay);
    }

    function testRandomAcctCannotSetVotingDelay(address random, uint256 newVotingDelay) public {
        vm.assume(_isNotReservedAddress(random));
        vm.assume(newVotingDelay >= MINIMUM_DELAY && newVotingDelay <= MAXIMUM_DELAY);
        // setup
        vm.expectRevert(bytes("!queen"));
        // execute
        vm.prank(random);
        serpentor.setVotingDelay(newVotingDelay);
    }

     function testShouldSetVotingDelay(address random, uint256 newVotingDelay) public {
        vm.assume(_isNotReservedAddress(random));
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

    function _setupVotingBalancesToQuorum(address[ARR_SIZE] memory voters) internal returns (uint256[ARR_SIZE] memory) {
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
    function _countVotes(uint256[ARR_SIZE] memory votes) internal pure returns (uint256) {
        uint256 total;
        for (uint i = 0; i < votes.length; i++) {
           total += votes[i];
        }

        return total;
    }

    function _noZeroVotes(uint8[ARR_SIZE] memory votes) internal pure returns (bool) {
        for (uint i = 0; i < votes.length; i++) {
           if (votes[i] == 0) {
             return false;
           }
        }

        return true;
    }


    function _setupTestProposal(
        address grantProposer, 
        uint256 votes
    ) internal returns (ProposalAction[] memory) {
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

    function _submitQueuedTestProposal(
        address[ARR_SIZE] memory voters,
        ProposalAction[] memory proposalActions, 
        address _proposer
    ) internal returns (uint256 proposalId , uint256 expectedETA) {
        uint256[ARR_SIZE] memory votes = _setupVotingBalancesToQuorum(voters);
        skip(1 days);
       
        uint256 voteCount = _countVotes(votes);
        assertTrue(voteCount > serpentor.quorumVotes());
    
        proposalId = _submitActiveTestProposal(proposalActions, _proposer);

        _executeVoting(voters, proposalId, 1); // for
        
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

    function _submitDefeatedTestProposal(
        address[ARR_SIZE] memory voters,
        ProposalAction[] memory proposalActions, 
        address _proposer
    ) internal returns (uint256 proposalId) {
        uint256[ARR_SIZE] memory votes = _setupVotingBalancesToQuorum(voters);
        skip(1 days);
       
        uint256 voteCount = _countVotes(votes);
        assertTrue(voteCount > serpentor.quorumVotes());
    
        proposalId = _submitActiveTestProposal(proposalActions, _proposer);

        _executeVoting(voters, proposalId, 0); // against
        
        Proposal memory proposal = serpentor.proposals(proposalId);
        vm.roll(proposal.endBlock + 2);
        
        assertEq(serpentor.ordinalState(proposalId), uint8(ProposalState.DEFEATED));
    }

    function _executeVoting(
        address[ARR_SIZE] memory voters,
        uint256 proposalId,
        uint8 support
    ) internal {
        // execute voting
        for (uint i = 0; i < voters.length; i++) {
            hoax(voters[i]);
            serpentor.vote(proposalId, support);
        }
    }

    function _submitActiveTestProposal(
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

     function _submitPendingTestProposal(
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

    function _setupReservedAddress() internal {
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

    function _assertVotes(Proposal memory proposal, uint256 votes, uint8 support) internal {
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

    function _isNotReservedAddress(address account) internal view returns (bool) {
        return !reserved[account];
    }

    function _noReservedAddress(address[ARR_SIZE] memory accounts) internal view returns (bool) {
        for (uint i = 0; i < accounts.length; i++)
             if (reserved[accounts[i]]) {
                return false;
             }
        return true;
    }

    function _noDuplicates(address[ARR_SIZE] memory accounts) internal returns (bool) {
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
