// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {SerpentorBravo} from "./interfaces/SerpentorBravo.sol";
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

    function testCannotProposeBelowThreshold(uint256 balance) public {
        vm.assume(balance < THRESHOLD);
        // setup
        address yoloProposer = address(0xBEEF);
        deal(address(token), yoloProposer, balance);


    }

}
