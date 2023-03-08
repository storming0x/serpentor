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
    uint256 public constant transferAmount = 1e18;

    address public admin = address(1);
    address public factory = address(2);
    address public objectoor = address(3);
    address public mediumVoter = address(4);
    address public whaleVoter1 = address(5);
    address public whaleVoter2 = address(6);
    address public knight = address(7);
    address public smallVoter = address(8);
    address public grantee = address(0xABCD);
    
    // test helper fields
    address[] public reservedList;
    mapping(address => bool) public isVoter; // for tracking duplicates in fuzzing
    mapping(address => bool) public reserved; // for tracking duplicates in fuzzing


    // events
    event MotionCreated(
        uint256 motionId, 
        address indexed proposer,
        address[] targets, 
        uint256[] values, 
        string[] signatures, 
        bytes[] calldatas,
        uint256 eta
    );

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

        _setupReservedAddress();

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

        // setup token balances
        deal(address(token), objectoor, QUORUM + 1);
        deal(address(token), smallVoter, 1e18);
        deal(address(token), mediumVoter, 10e18);
        deal(address(token), whaleVoter1, 300e18);
        deal(address(token), whaleVoter2, 250e18);
        deal(address(token), address(timelock), 1000e18);
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


    function _setupReservedAddress() internal {
        reservedList = [
            admin, 
            factory,
            smallVoter, 
            mediumVoter, 
            whaleVoter1, 
            whaleVoter2, 
            objectoor,
            knight,
            grantee,
            address(0),
            address(timelock),
            address(fastTrack),
            address(token)
        ];
        for (uint i = 0; i < reservedList.length; i++)
             reserved[reservedList[i]] = true;
    }

    function testOnlyApprovedFactoryCanMotion(address random) public {
        vm.assume(!reserved[random]);
        vm.assume(random != factory);

        // setup
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(token);
        values[0] = 0;
        signatures[0] = "";
        calldatas[0] = abi.encodeWithSelector(IERC20.transfer.selector, grantee, transferAmount);
        vm.expectRevert(bytes("!factory"));

        //execute
        hoax(random);
        fastTrack.createMotion(targets, values, signatures, calldatas);
    }
}
