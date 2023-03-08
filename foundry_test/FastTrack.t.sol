// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";
import {DualTimelock} from "./interfaces/DualTimelock.sol";
import {FastTrack} from "./interfaces/FastTrack.sol";
import {GovToken} from "./utils/GovToken.sol";

contract FastTrackTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    DualTimelock private timelock;
    ERC20 private token;
    FastTrack private fastTrack;

    uint256 public delay = 2 days;
    uint256 public fastTrackDelay = 1 days;
    uint public constant QUORUM = 300e18;

    address public admin = address(1);
    address public factory = address(2);
    address public objectoor = address(3);
    address public mediumVoter = address(4);
    address public whaleVoter1 = address(5);
    address public whaleVoter2 = address(6);
    address public knight = address(7);
    address public smallVoter = address(8);
    address public grantee = address(0xABCD);

    mapping(address => bool) public isVoter; // for tracking duplicates in fuzzing

    function setUp() public {
         // deploy token
        token = ERC20(new GovToken(18));
        console.log("address for GovToken: ", address(token));

        bytes memory argsFastTrack = abi.encode(address(token), admin);
        fastTrack = FastTrack(vyperDeployer.deployContract("src/", "FastTrack", argsFastTrack));
        console.log("address for FastTrack: ", address(fastTrack));

        bytes memory args = abi.encode(admin, address(fastTrack), delay, fastTrackDelay);
        timelock = DualTimelock(vyperDeployer.deployContract("src/", "DualTimelock", args));
        console.log("address for DualTimelock: ", address(timelock));

        // vm traces
        vm.label(address(timelock), "DualTimelock");
        vm.label(address(token), "Token");
        vm.label(factory, "factory");
        vm.label(objectoor, "objectoor");
        vm.label(smallVoter, "smallVoter");
        vm.label(mediumVoter, "mediumVoter");
        vm.label(whaleVoter1, "whaleVoter1");
        vm.label(whaleVoter2, "whaleVoter2");
        vm.label(knight, "knight");
        vm.label(grantee, "grantee");

        // setup voting balances
        deal(address(token), objectoor, QUORUM + 1);
        deal(address(token), smallVoter, 1e18);
        deal(address(token), mediumVoter, 10e18);
        deal(address(token), whaleVoter1, 300e18);
        deal(address(token), whaleVoter2, 250e18);
    }

    function testSetup() public {
        assertNeq(address(timelock), address(0));
        assertNeq(address(fastTrack), address(0));

        assertEq(address(timelock.admin()), admin);
        assertEq(timelock.delay(), delay);
        assertEq(timelock.fastTrackDelay(), fastTrackDelay);
        assertEq(fastTrack.admin(), admin);
        assertEq(fastTrack.token(), address(token));
    }
}
