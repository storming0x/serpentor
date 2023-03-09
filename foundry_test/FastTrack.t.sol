// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";
import {DualTimelock} from "./interfaces/DualTimelock.sol";
import {
    FastTrack, 
    Factory,
    Motion
} from "./interfaces/FastTrack.sol";
import {GovToken} from "./utils/GovToken.sol";

contract FastTrackTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    DualTimelock private timelock;
    ERC20 private token;
    FastTrack private fastTrack;

    uint256 public delay = 2 days;
    uint256 public fastTrackDelay = 1 days;
    uint public constant QUORUM = 2000;
    uint256 public constant transferAmount = 1e18;
    uint256 public constant MAX_OPERATIONS = 10;
    uint256 public constant MIN_OBJECTIONS_THRESHOLD = 100; // 1%
    uint256 public constant MAX_OBJECTIONS_THRESHOLD = 3000; // 30%
    uint256 public constant MIN_MOTION_DURATION = 16 hours;

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
        uint256 indexed motionId, 
        address indexed proposer,
        address[] targets, 
        uint256[] values, 
        string[] signatures, 
        bytes[] calldatas,
        uint256 eta,
        uint256 snapshotBlock,
        uint256 objectionsThreshold
    );

    event MotionFactoryAdded(
        address indexed factory,
        uint256 objectionsThreshold,
        uint256 motionDuration
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
        // setup factory
        hoax(admin);
        fastTrack.addMotionFactory(factory, QUORUM, 1 days);

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
        deal(address(token), objectoor, QUORUM);
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
        assertTrue(fastTrack.factories(factory).isFactory);
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

    function testRandomAcctCannotAddMotionFactory(address random) public {
        vm.assume(!reserved[random]);

        // setup
        vm.expectRevert(bytes("!admin"));

        //execute
        hoax(random);
        fastTrack.addMotionFactory(random, MIN_OBJECTIONS_THRESHOLD, MIN_MOTION_DURATION);
    }

    function testMotionFactoryDurationCannotBeLessThanMinimum(address random, uint256 objectionsThreshold, uint32 motionDuration) public {
        vm.assume(!reserved[random]);
        vm.assume(objectionsThreshold >= MIN_OBJECTIONS_THRESHOLD);
        vm.assume(motionDuration < MIN_MOTION_DURATION); 

        // setup
        vm.expectRevert(bytes("!motion_duration"));

        //execute
        hoax(admin);
        fastTrack.addMotionFactory(random, objectionsThreshold, motionDuration);
    }

    function testMotionFactoryObjectionsThresholdCannotBeLessThanMinimum(address random, uint256 objectionsThreshold) public {
        vm.assume(!reserved[random]);
        vm.assume(objectionsThreshold < MIN_OBJECTIONS_THRESHOLD);

        // setup
        vm.expectRevert(bytes("!min_objections_threshold"));

        //execute
        hoax(admin);
        fastTrack.addMotionFactory(random, objectionsThreshold, MIN_MOTION_DURATION);
    }

    function testMotionFactoryObjectionsThresholdCannotBeGreaterThanMaximum(address random, uint256 objectionsThreshold) public {
        vm.assume(!reserved[random]);
        vm.assume(objectionsThreshold > MAX_OBJECTIONS_THRESHOLD);

        // setup
        vm.expectRevert(bytes("!max_objections_threshold"));

        //execute
        hoax(admin);
        fastTrack.addMotionFactory(random, objectionsThreshold, MIN_MOTION_DURATION);
    }

    function testCannotAddFactoryTwice() public {
        // setup
        vm.expectRevert(bytes("!factory_exists"));

        //execute
        hoax(admin);
        fastTrack.addMotionFactory(factory, MIN_OBJECTIONS_THRESHOLD, 1 days);
    }

    function testShouldAddMotionFactory(address random, uint256 objectionsThreshold, uint32 motionDuration) public {
        vm.assume(!reserved[random]);
        vm.assume(objectionsThreshold >= MIN_OBJECTIONS_THRESHOLD && objectionsThreshold <= MAX_OBJECTIONS_THRESHOLD);
        vm.assume(motionDuration >= MIN_MOTION_DURATION); 

        // setup
        vm.expectEmit(false, false, false, false);
        emit MotionFactoryAdded(factory, objectionsThreshold, motionDuration);

        //execute
        hoax(admin);
        fastTrack.addMotionFactory(random, objectionsThreshold, motionDuration);

        // assert
        assertTrue(fastTrack.factories(random).isFactory);
        assertEq(fastTrack.factories(random).motionDuration, motionDuration);
        assertEq(fastTrack.factories(random).objectionsThreshold, objectionsThreshold);
    }

    function testOnlyApprovedFactoryCanCreateMotion(address random) public {
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

    function testCannotCreateMotionWithZeroOps() public {
        // setup
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        string[] memory signatures = new string[](0);
        bytes[] memory calldatas = new bytes[](0);
        vm.expectRevert(bytes("!no_targets"));

        //execute
        hoax(factory);
        fastTrack.createMotion(targets, values, signatures, calldatas);
    }

    function testCannotCreateMotionWithDifferentLenArrays() public {
        // setup
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](2);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(token);
        values[0] = 0;
        values[1] = 0;
        signatures[0] = "";
        calldatas[0] = abi.encodeWithSelector(IERC20.transfer.selector, grantee, transferAmount);
        vm.expectRevert(bytes("!len_mismatch"));

        //execute
        hoax(factory);
        fastTrack.createMotion(targets, values, signatures, calldatas);
    }

    function testCannotCreateMotionWithTooManyOperations() public {
        // setup
        address[] memory targets = new address[](MAX_OPERATIONS + 1);
        uint256[] memory values = new uint256[](MAX_OPERATIONS + 1);
        string[] memory signatures = new string[](MAX_OPERATIONS + 1);
        bytes[] memory calldatas = new bytes[](MAX_OPERATIONS + 1);
        for (uint i = 0; i < MAX_OPERATIONS + 1; i++) {
            targets[i] = address(token);
            values[i] = 0;
            signatures[i] = "";
            calldatas[i] = abi.encodeWithSelector(IERC20.transfer.selector, grantee, transferAmount);
        }
        // vyper reverts
        vm.expectRevert();

        //execute
        hoax(factory);
        fastTrack.createMotion(targets, values, signatures, calldatas);
    }

    function testShouldCreateMotion(uint8 operations) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        address[] memory targets = new address[](operations);
        uint256[] memory values = new uint256[](operations);
        string[] memory signatures = new string[](operations);
        bytes[] memory calldatas = new bytes[](operations);
        for (uint i = 0; i < operations; i++) {
            targets[i] = address(token);
            values[i] = 0;
            signatures[i] = "";
            calldatas[i] = abi.encodeWithSelector(IERC20.transfer.selector, grantee, transferAmount);
        }

        // setup
        vm.expectEmit(true, true, false, false);
        emit MotionCreated(
            1, 
            factory, 
            targets, 
            values, 
            signatures, 
            calldatas, 
            block.timestamp + fastTrack.factories(factory).motionDuration,
            block.number,
            fastTrack.factories(factory).objectionsThreshold
        );

        //execute
        hoax(factory);
        fastTrack.createMotion(targets, values, signatures, calldatas);

        // assert
        Motion memory motion = fastTrack.motions(1);
        assertEq(motion.proposer, factory);
        assertEq(motion.eta, block.number + fastTrack.factories(factory).motionDuration);
        assertEq(motion.objectionsThreshold, fastTrack.factories(factory).objectionsThreshold);
        assertEq(motion.objections, 0);
        assertEq(motion.queued, false);
        assertEq(motion.targets.length, targets.length);
        assertEq(motion.values.length, values.length);
        assertEq(motion.signatures.length, signatures.length);
        assertEq(motion.calldatas.length, calldatas.length);
        for (uint i = 0; i < targets.length; i++) {
            assertEq(motion.targets[i], targets[i]);
            assertEq(motion.values[i], values[i]);
            assertEq(motion.signatures[i], signatures[i]);
            assertEq(motion.calldatas[i], calldatas[i]);
        }
        assertEq(fastTrack.lastMotionId(), 1);
    }
}
