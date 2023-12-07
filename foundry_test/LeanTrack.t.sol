// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";
import {DualTimelock} from "./interfaces/DualTimelock.sol";
import {
    LeanTrack, 
    Factory,
    Motion
} from "./interfaces/LeanTrack.sol";
import {GovToken} from "./utils/GovToken.sol";

contract LeanTrackTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    DualTimelock private timelock;
    ERC20 private token;
    LeanTrack private leanTrack;
    GovToken private govToken;

    uint256 public delay = 2 days;
    uint256 public leanTrackDelay = 1 days;
    uint256 public factoryMotionDuration = 1 days;
    uint256 public constant HUNDRED_PCT = 10000;
    uint256 public constant TOKEN_SUPPLY =  30000 * 10**uint256(18);
    uint256 public constant QUORUM = 2000; // 20%
    uint256 public constant QUORUM_AMOUNT = TOKEN_SUPPLY * QUORUM / HUNDRED_PCT;
    uint256 public constant transferAmount = 1e18;
    uint256 public constant MAX_OPERATIONS = 10;
    uint256 public constant MIN_OBJECTIONS_THRESHOLD = 100; // 1%
    uint256 public constant MAX_OBJECTIONS_THRESHOLD = 3000; // 30%
    uint256 public constant MIN_MOTION_DURATION = 1; // 1 second

    address public admin = address(1);
    address public factory = address(2);
    address public objectoor = address(3);
    address public mediumVoter = address(4);
    address public whaleVoter1 = address(5);
    address public whaleVoter2 = address(6);
    address public knight = address(7);
    address public smallVoter = address(8);
    address public grantee = address(0xABCD);
    address public executor = address(7);
    
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

    event MotionQueued(
        uint256 indexed motionId,
        bytes32[] txHashes,
        uint256 eta
    );

    event MotionObjected(
        uint256 indexed motionId,
        address indexed objector,
        uint256 objectorsBalance,
        uint256 newObjectionsAmount,
        uint256 newObjectionsAmountPct
    );

    event MotionRejected(
        uint256 indexed motionId
    );

    event MotionCanceled(
        uint256 indexed motionId
    );

    event MotionFactoryAdded(
        address indexed factory,
        uint256 objectionsThreshold,
        uint256 motionDuration
    );

    event MotionFactoryRemoved(
        address indexed factory
    );

    event ExecutorAdded(
        address indexed executor
    );

    event ExecutorRemoved(
        address indexed executor
    );

    event Paused(
        address indexed account
    );
    
    event Unpaused(
        address indexed account
    );

    function setUp() public {
         // deploy token
        govToken = new GovToken(18);
        token = ERC20(govToken);
        console.log("address for GovToken: ", address(token));
        
        bytes memory args = abi.encode(admin, address(0), delay, leanTrackDelay);
        timelock = DualTimelock(vyperDeployer.deployContract("src/", "DualTimelock", args));
        console.log("address for DualTimelock: ", address(timelock));

        bytes memory argsLeanTrack = abi.encode(address(token), admin, address(timelock), knight);
        leanTrack = LeanTrack(vyperDeployer.deployContract("src/", "LeanTrack", argsLeanTrack));
        console.log("address for LeanTrack: ", address(leanTrack));

        hoax(address(timelock));
        timelock.setPendingLeanTrack(address(leanTrack));
        
        hoax(address(knight));
        leanTrack.acceptTimelockAccess();


        _setupReservedAddress();
        // setup factory
        hoax(admin);
        leanTrack.addMotionFactory(factory, QUORUM, factoryMotionDuration);

        // add executor
        hoax(admin);
        leanTrack.addExecutor(address(knight));

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
        assertNeq(address(leanTrack), address(0));

        assertEq(address(timelock.admin()), admin);
        assertEq(timelock.delay(), delay);
        assertEq(timelock.leanTrackDelay(), leanTrackDelay);
        assertEq(leanTrack.admin(), admin);
        assertEq(leanTrack.token(), address(token));
        assertTrue(leanTrack.factories(factory).isFactory);
        assertEq(leanTrack.factories(factory).objectionsThreshold, QUORUM);
        assertEq(leanTrack.factories(factory).motionDuration, factoryMotionDuration);
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
            address(leanTrack),
            address(token),
            address(this)
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
        leanTrack.addMotionFactory(random, MIN_OBJECTIONS_THRESHOLD, MIN_MOTION_DURATION);
    }

    function testMotionFactoryDurationCannotBeLessThanMinimum(address random, uint256 objectionsThreshold, uint32 motionDuration) public {
        vm.assume(!reserved[random]);
        vm.assume(objectionsThreshold >= MIN_OBJECTIONS_THRESHOLD);
        vm.assume(motionDuration < MIN_MOTION_DURATION); 

        // setup
        vm.expectRevert(bytes("!motion_duration"));

        //execute
        hoax(admin);
        leanTrack.addMotionFactory(random, objectionsThreshold, motionDuration);
    }

    function testMotionFactoryObjectionsThresholdCannotBeLessThanMinimum(address random, uint256 objectionsThreshold) public {
        vm.assume(!reserved[random]);
        vm.assume(objectionsThreshold < MIN_OBJECTIONS_THRESHOLD);

        // setup
        vm.expectRevert(bytes("!min_objections_threshold"));

        //execute
        hoax(admin);
        leanTrack.addMotionFactory(random, objectionsThreshold, MIN_MOTION_DURATION);
    }

    function testMotionFactoryObjectionsThresholdCannotBeGreaterThanMaximum(address random, uint256 objectionsThreshold) public {
        vm.assume(!reserved[random]);
        vm.assume(objectionsThreshold > MAX_OBJECTIONS_THRESHOLD);

        // setup
        vm.expectRevert(bytes("!max_objections_threshold"));

        //execute
        hoax(admin);
        leanTrack.addMotionFactory(random, objectionsThreshold, MIN_MOTION_DURATION);
    }

    function testCannotAddFactoryTwice() public {
        // setup
        vm.expectRevert(bytes("!factory_exists"));

        //execute
        hoax(admin);
        leanTrack.addMotionFactory(factory, MIN_OBJECTIONS_THRESHOLD, 1 days);
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
        leanTrack.addMotionFactory(random, objectionsThreshold, motionDuration);

        // assert
        assertTrue(leanTrack.factories(random).isFactory);
        assertEq(leanTrack.factories(random).motionDuration, motionDuration);
        assertEq(leanTrack.factories(random).objectionsThreshold, objectionsThreshold);
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
        leanTrack.createMotion(targets, values, signatures, calldatas);
    }

    function testShouldRemoveFactory(address random, uint256 objectionsThreshold, uint32 motionDuration) public {
        vm.assume(!reserved[random]);
        vm.assume(objectionsThreshold >= MIN_OBJECTIONS_THRESHOLD && objectionsThreshold <= MAX_OBJECTIONS_THRESHOLD);
        vm.assume(motionDuration >= MIN_MOTION_DURATION); 

        // setup
        vm.expectEmit(false, false, false, false);
        emit MotionFactoryAdded(factory, objectionsThreshold, motionDuration);
        // add factory
        hoax(admin);
        leanTrack.addMotionFactory(random, objectionsThreshold, motionDuration);

        // assert factory added
        assertTrue(leanTrack.factories(random).isFactory);
        assertEq(leanTrack.factories(random).motionDuration, motionDuration);
        assertEq(leanTrack.factories(random).objectionsThreshold, objectionsThreshold);

        // execute remove factory
        vm.expectEmit(false, false, false, false);
        emit MotionFactoryRemoved(random);

        //execute
        hoax(admin);
        leanTrack.removeMotionFactory(random);

        // assert factory removed
        assertTrue(!leanTrack.factories(random).isFactory);
    }

    function testOnlyAdminCanRemoveFactory(address random, uint256 objectionsThreshold, uint32 motionDuration) public {
        vm.assume(!reserved[random]);
        vm.assume(objectionsThreshold >= MIN_OBJECTIONS_THRESHOLD && objectionsThreshold <= MAX_OBJECTIONS_THRESHOLD);
        vm.assume(motionDuration >= MIN_MOTION_DURATION); 

        // setup
        vm.expectEmit(false, false, false, false);
        emit MotionFactoryAdded(factory, objectionsThreshold, motionDuration);
        // add factory
        hoax(admin);
        leanTrack.addMotionFactory(random, objectionsThreshold, motionDuration);

        // assert factory added
        assertTrue(leanTrack.factories(random).isFactory);
        assertEq(leanTrack.factories(random).motionDuration, motionDuration);
        assertEq(leanTrack.factories(random).objectionsThreshold, objectionsThreshold);

        // setup
        vm.expectRevert(bytes("!admin"));

        //execute
        hoax(random);
        leanTrack.removeMotionFactory(random);
    }

    function testCannotRemoveFactoryThatDoesNotExist(address random) public {
        vm.assume(!reserved[random]);

        // setup
        vm.expectRevert(bytes("!factory_exists"));

        //execute
        hoax(admin);
        leanTrack.removeMotionFactory(random);
    }

    function testOnlyAdminCanAddExecutor(address random) public {
        vm.assume(!reserved[random]);

        // setup
        vm.expectRevert(bytes("!admin"));

        //execute
        hoax(random);
        leanTrack.addExecutor(random);
    }

    function testCannotAddExecutorTwice(address random) public {
        vm.assume(!reserved[random]);

        // setup
        vm.expectEmit(false, false, false, false);
        emit ExecutorAdded(random);

        //execute
        hoax(admin);
        leanTrack.addExecutor(random);

        // setup
        vm.expectRevert(bytes("!executor_exists"));

        //execute
        hoax(admin);
        leanTrack.addExecutor(random);
    }

    function testShouldAddExecutor(address random) public {
        vm.assume(!reserved[random]);

        // setup
        vm.expectEmit(false, false, false, false);
        emit ExecutorAdded(random);

        //execute
        hoax(admin);
        leanTrack.addExecutor(random);

        // assert
        assertTrue(leanTrack.executors(random));
    }

    function testOnlyAdminCanRemoveExecutor(address random) public {
        vm.assume(!reserved[random]);

        // setup
        vm.expectRevert(bytes("!admin"));

        //execute
        hoax(random);
        leanTrack.removeExecutor(random);
    }

    function testCannotRemoveExecutorThatDoesNotExist(address random) public {
        vm.assume(!reserved[random]);

        // setup
        vm.expectRevert(bytes("!executor_exists"));

        //execute
        hoax(admin);
        leanTrack.removeExecutor(random);
    }

    function testShouldRemoveExecutor(address random) public {
        vm.assume(!reserved[random]);

        // setup
        vm.expectEmit(false, false, false, false);
        emit ExecutorAdded(random);

        //execute
        hoax(admin);
        leanTrack.addExecutor(random);

        // assert
        assertTrue(leanTrack.executors(random));

        // setup
        vm.expectEmit(false, false, false, false);
        emit ExecutorRemoved(random);

        //execute
        hoax(admin);
        leanTrack.removeExecutor(random);

        // assert
        assertTrue(!leanTrack.executors(random));
    }

    function testOnlyAdminCanSetKnight(address random) public {
        vm.assume(!reserved[random]);

        // setup
        vm.expectRevert(bytes("!admin"));

        //execute
        hoax(random);
        leanTrack.setKnight(random);
    }

    function testKnightCannotBeAddressZero() public {
        // setup
        vm.expectRevert(bytes("!knight"));

        //execute
        hoax(admin);
        leanTrack.setKnight(address(0));
    }

    function testOnlyKnightCanPauseLeanTrack(address random) public {
        vm.assume(!reserved[random]);

        // setup
        vm.expectRevert(bytes("!knight"));

        //execute
        hoax(random);
        leanTrack.pause();
    }

    function testShouldPauseLeanTrack() public {
        // setup
        vm.expectEmit(false, false, false, false);
        emit Paused(knight);

        //execute
        hoax(knight);
        leanTrack.pause();

        // assert
        assertTrue(leanTrack.paused());
    }


    // MOTION TESTS

    function testCannotCreateMotionWithZeroOps() public {
        // setup
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        string[] memory signatures = new string[](0);
        bytes[] memory calldatas = new bytes[](0);
        vm.expectRevert(bytes("!no_targets"));

        //execute
        hoax(factory);
        leanTrack.createMotion(targets, values, signatures, calldatas);
    }

    function testCannotCreateMotionWhenPaused() public {
        // setup
        hoax(knight);
        leanTrack.pause();

        vm.expectRevert(bytes("!paused"));

        //execute
        hoax(factory);
        leanTrack.createMotion(new address[](0), new uint256[](0), new string[](0), new bytes[](0));
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
        leanTrack.createMotion(targets, values, signatures, calldatas);
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
        leanTrack.createMotion(targets, values, signatures, calldatas);
    }

    function testShouldCreateMotion(uint8 operations) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        address[] memory targets;
        uint256[] memory values;
        string[] memory signatures;
        bytes[] memory calldatas;
        bytes32[] memory hashes;
        uint256 totalAmount;
        
        (targets, values, signatures, calldatas, hashes, totalAmount) = _createMotionTrxs(operations);

        // setup
        vm.expectEmit(true, true, false, false);
        emit MotionCreated(
            1, 
            factory, 
            targets, 
            values, 
            signatures, 
            calldatas, 
            block.timestamp + leanTrack.factories(factory).motionDuration,
            block.number,
            leanTrack.factories(factory).objectionsThreshold
        );

        //execute
        hoax(factory);
        uint256 motionId = leanTrack.createMotion(targets, values, signatures, calldatas);

        // assert
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.proposer, factory);
        assertEq(motion.timeForQueue, block.timestamp + leanTrack.factories(factory).motionDuration);
        assertEq(motion.objectionsThreshold, leanTrack.factories(factory).objectionsThreshold);
        assertEq(motion.objections, 0);
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
        assertEq(leanTrack.lastMotionId(), 1);
    }

    function testCannotQueueMotionWhenPaused(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations);
        hoax(knight);
        leanTrack.pause();
        vm.expectRevert(bytes("!paused"));

        //execute
        hoax(random);
        leanTrack.queueMotion(motionId);
    }
    
    function testCannotQueueMotionBeforeEta(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup

        uint256 motionId;
        (motionId,) = _createMotion(operations);
        vm.expectRevert(bytes("!timeForQueue"));

        //execute
        hoax(random);
        leanTrack.queueMotion(motionId);
    }

    function testCannotQueueUnexistingMotion(uint256 operations, address random, uint256 unexistingMotiondId) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations); // motion 1
        vm.assume(unexistingMotiondId != motionId);
        vm.expectRevert(bytes("!motion_exists"));
        
        //execute
        hoax(random);
        leanTrack.queueMotion(unexistingMotiondId); // doesnt exist
    }

    function testShouldQueueMotion(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        uint256 totalAmount;
        bytes32[] memory trxHashes;
        address[] memory targets;
        uint256[] memory values;
        string[] memory signatures;
        bytes[] memory calldatas;
        // create test motion transactions
        (targets, values, signatures, calldatas, trxHashes, totalAmount) = _createMotionTrxs(operations);

        hoax(factory);
        motionId = leanTrack.createMotion(targets, values, signatures, calldatas);
        
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.expectEmit(true, true, false, false);
        emit MotionQueued(motionId, trxHashes, motion.timeForQueue + leanTrackDelay);

        vm.warp(motion.timeForQueue); //skip to time for queue

        //execute
        hoax(random);
        bytes32[] memory queuedTrxHashes = leanTrack.queueMotion(motionId);

        //assert motion has been queued and eta has been set
        motion = leanTrack.motions(motionId);
        assertEq(motion.isQueued, true);
        assertEq(motion.eta, motion.timeForQueue + leanTrackDelay);
        // check trx hashes where correctly queued
        for (uint i = 0; i < trxHashes.length; i++) {
            assertEq(trxHashes[i], queuedTrxHashes[i]);
            assertEq(timelock.queuedRapidTransactions(queuedTrxHashes[i]), true);
        }
        // check that the motion is not queued again
        assertEq(leanTrack.motions(motionId).isQueued, true);
    }

    function testCannotQueueMotionTwice(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.warp(motion.timeForQueue); //skip to eta

        //execute
        hoax(random);
        leanTrack.queueMotion(motionId);

        vm.expectRevert(bytes("!motion_queued"));
        leanTrack.queueMotion(motionId);
    }

    function testCannotEnactMotionWhenPaused(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.warp(motion.timeForQueue); //skip to eta

        //execute
        hoax(random);
        leanTrack.queueMotion(motionId);

        hoax(knight);
        leanTrack.pause();
        vm.expectRevert(bytes("!paused"));

        //execute
        hoax(executor); 
        leanTrack.enactMotion(motionId);
    }

    function testOnlyExecutorsCanCallEnactMotion(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.warp(motion.timeForQueue); //skip to eta

        //execute
        hoax(random);
        leanTrack.queueMotion(motionId);

        vm.expectRevert(bytes("!executor"));
        hoax(random);
        leanTrack.enactMotion(motionId);
    }

    function testCannotEnactUnexistingMotion(uint256 operations, address random, uint256 unexistingMotiondId) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations); // motion 1
        vm.assume(unexistingMotiondId != motionId);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.warp(motion.timeForQueue); //skip to eta

        //execute
        hoax(random);
        leanTrack.queueMotion(motionId);

        vm.expectRevert(bytes("!motion_exists"));
        hoax(executor); 
        leanTrack.enactMotion(unexistingMotiondId); // doesnt exist
    }

    function testCannotEnactMotionThatIsntQueued(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.expectRevert(bytes("!motion_queued"));
        hoax(executor); 
        leanTrack.enactMotion(motionId);
    }

    function testCannotEnactMotionBeforeEta(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.warp(motion.timeForQueue); //skip to eta

        //execute
        hoax(random);
        leanTrack.queueMotion(motionId);

        vm.expectRevert(bytes("!eta"));
        hoax(executor); 
        leanTrack.enactMotion(motionId); // not enough time has passed since delay
    }

    function testShouldEnactQueuedMotion(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        uint256 expectedAmount;
        address[] memory targets;
        uint256[] memory values;
        string[] memory signatures;
        bytes[] memory calldatas;
        bytes32[] memory trxHashes;
        uint256 eta = block.timestamp + factoryMotionDuration + leanTrackDelay;
        (targets, values, signatures, calldatas, trxHashes, expectedAmount) = _createMotionTrxs(operations);
        // create motion
        hoax(factory);
        motionId = leanTrack.createMotion(targets, values, signatures, calldatas);

        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.warp(motion.timeForQueue); //skip to eta

        // setup queue motion
        hoax(random);
        leanTrack.queueMotion(motionId);

        motion = leanTrack.motions(motionId);
        assertTrue(motion.eta != 0);
        assertEq(motion.eta, eta);
        vm.warp(motion.eta); //skip to eta

        //execute
        hoax(executor); 
        leanTrack.enactMotion(motionId);

        //assert motion has been enacted
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, 0);
        // check transaction was executed
        assertEq(token.balanceOf(grantee), expectedAmount);
    }

    function testCannotObjectToMotionThatDoesntExist(uint256 operations, address random, uint256 unexistingMotiondId) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations); // motion 1
        vm.assume(unexistingMotiondId != motionId);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.warp(motion.timeForQueue); //skip to eta

        //execute
        hoax(random);
        leanTrack.queueMotion(motionId);

        vm.expectRevert(bytes("!motion_exists"));
        hoax(objectoor); 
        leanTrack.objectToMotion(unexistingMotiondId); // doesnt exist
    }

    function testCannotObjectToQueuedMotion(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.warp(motion.timeForQueue); //skip to eta

        //execute
        hoax(random);
        leanTrack.queueMotion(motionId);

        vm.expectRevert(bytes("!motion_queued"));
        hoax(objectoor); 
        leanTrack.objectToMotion(motionId); // already queued   
    }

    function testCannotObjectToMotionAfterTimeForQueuePasses(uint256 operations, address random) public {
        vm.assume(operations > 0 && operations <= MAX_OPERATIONS);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(operations);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.warp(motion.timeForQueue + 1); //skip to eta without queueing the motion

        vm.expectRevert(bytes("!timeForQueue"));
        hoax(objectoor); 
        leanTrack.objectToMotion(motionId); // timeForQueue has passed  
    }

    function testShouldObjectToMotionWithVotingPowerLessThanThreshold(address random, uint256 votingBalance) public {
        vm.assume(votingBalance > 0 && votingBalance < QUORUM_AMOUNT);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, 0);
        assertEq(motion.objectionsThreshold, QUORUM);
        deal(address(token), random, votingBalance);
        uint256 votingBalanceForObjector = token.balanceOf(random);
        uint256 votingBalanceForObjectorPct = (votingBalanceForObjector * HUNDRED_PCT) / TOKEN_SUPPLY;

        // check for event
        vm.expectEmit(false, false, false, false);
        emit MotionObjected(motionId, random, votingBalanceForObjector, votingBalanceForObjector, votingBalanceForObjectorPct);

        //execute
        hoax(random);
        leanTrack.objectToMotion(motionId);

        //assert motion has correct amount of objections
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, votingBalanceForObjector);
    }

    function testShouldUseLowerVotingBalanceForObjection(address random, uint256 votingBalance) public {
        vm.assume(votingBalance > 0 && votingBalance < QUORUM_AMOUNT);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, 0);
        assertEq(motion.objectionsThreshold, QUORUM);
        // setup voting power
        govToken._setUseBalanceOfForVotingPower(false);
        // has lower balance at the time of the motion snapshot block
        govToken._setVotingPower(random, motion.snapshotBlock, votingBalance);
        uint256 votingBalanceForObjector = govToken.getPriorVotes(random, motion.snapshotBlock);
        uint256 votingBalanceForObjectorPct = (votingBalanceForObjector * HUNDRED_PCT) / TOKEN_SUPPLY;

        // skip block numbers
        vm.roll(block.number + 2);
        // give objector more voting power than Quorum at current block number
        govToken._setVotingPower(random, block.number, QUORUM_AMOUNT + 1);

        // check for event
        vm.expectEmit(false, false, false, false);
        emit MotionObjected(motionId, random, votingBalanceForObjector, votingBalanceForObjector, votingBalanceForObjectorPct);

        //execute
        hoax(random);
        leanTrack.objectToMotion(motionId);

        //assert motion has correct amount of objections
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        // should use lower voting balance
        assertEq(motion.objections, votingBalanceForObjector);
    }

    function testCannotObjectTwiceToSameMotion(address random, uint256 votingBalance) public {
        vm.assume(votingBalance > 0 && votingBalance < QUORUM_AMOUNT);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, 0);
        assertEq(motion.objectionsThreshold, QUORUM);
        deal(address(token), random, votingBalance);
        uint256 votingBalanceForObjector = token.balanceOf(random);
        uint256 votingBalanceForObjectorPct = (votingBalanceForObjector * HUNDRED_PCT) / TOKEN_SUPPLY;

        // check for event
        vm.expectEmit(false, false, false, false);
        emit MotionObjected(motionId, random, votingBalanceForObjector, votingBalanceForObjector, votingBalanceForObjectorPct);

        //execute
        hoax(random);
        leanTrack.objectToMotion(motionId);

        //assert motion has correct amount of objections
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, votingBalanceForObjector);

        vm.expectRevert(bytes("!already_objected"));
        hoax(random);
        leanTrack.objectToMotion(motionId); // already objected
    }

    function testCannotObjectToMotionWithZeroVotingBalance(address random) public {
        vm.assume(!reserved[random]);
        uint256 votingBalanceForObjector = token.balanceOf(random);
        vm.assume(votingBalanceForObjector == 0);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, 0);
        assertEq(motion.objectionsThreshold, QUORUM);

        vm.expectRevert(bytes("!voting_balance"));
        hoax(random);
        leanTrack.objectToMotion(motionId); // zero voting balance
    }

    function testShouldRejectMotionIfObjectionsReachedAboveThreshold(address random, uint256 votingBalance) public {
        vm.assume(votingBalance >= QUORUM_AMOUNT && votingBalance < TOKEN_SUPPLY);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, 0);
        assertEq(motion.objectionsThreshold, QUORUM);
        deal(address(token), random, votingBalance);
        uint256 votingBalanceForObjector = token.balanceOf(random);
        uint256 votingBalanceForObjectorPct = (votingBalanceForObjector * HUNDRED_PCT) / TOKEN_SUPPLY;

        // check for event
        vm.expectEmit(false, false, false, false);
        emit MotionObjected(motionId, random, votingBalanceForObjector, votingBalanceForObjector, votingBalanceForObjectorPct);

        // check for event
        vm.expectEmit(false, false, false, false);
        emit MotionRejected(motionId);

        //execute
        hoax(random); // has more than quorum
        leanTrack.objectToMotion(motionId); // should reject motion

        //assert motion has been deleted
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, 0);
    }

    function testRandomAcctCannotCanCancelMotion(address random) public {
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.expectRevert(bytes("!access"));
        hoax(random);
        leanTrack.cancelMotion(motionId);
    }

    function testCannotCancelUnexistingMotion(address random) public {
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.proposer, factory);

        vm.expectRevert(bytes("!motion_exists"));
        hoax(factory);
        leanTrack.cancelMotion(motionId + 1);
    }

    function testProposerCanCancelMotionBeforeQueued(address random) public {
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.proposer, factory);

        // check for event
        vm.expectEmit(false, false, false, false);
        emit MotionCanceled(motionId);

        //execute
        hoax(factory);
        leanTrack.cancelMotion(motionId);

        //assert motion has been deleted
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, 0);
    }

    function testKnightCanCancelMotionBeforeQueued(address random) public {
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.proposer, factory);

        // check for event
        vm.expectEmit(false, false, false, false);
        emit MotionCanceled(motionId);

        //execute
        hoax(knight);
        leanTrack.cancelMotion(motionId);

        //assert motion has been deleted
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, 0);
    }

    function testProposerCanCancelMotionAfterBeingQueued() public {
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.proposer, factory);

        // skip to timeForQueue
        vm.warp(motion.timeForQueue);

        hoax(factory);
        bytes32[] memory queuedTrxHashes = leanTrack.queueMotion(motionId);

        //assert trxHashes are queued in timelock
        for (uint256 i = 0; i < queuedTrxHashes.length; i++) {
            assertTrue(timelock.queuedRapidTransactions(queuedTrxHashes[i]));
        }

        // check for event
        vm.expectEmit(false, false, false, false);
        emit MotionCanceled(motionId);

        //execute
        hoax(factory);
        leanTrack.cancelMotion(motionId);

        //assert motion has been deleted
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, 0);

         //assert trxHashes are no longer queued in timelock
        for (uint256 i = 0; i < queuedTrxHashes.length; i++) {
            assertFalse(timelock.queuedRapidTransactions(queuedTrxHashes[i]));
        }
    }

    function testKnightCanCancelMotionAfterBeingQueued() public {
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.proposer, factory);

        // skip to timeForQueue
        vm.warp(motion.timeForQueue);

        hoax(factory);
        bytes32[] memory queuedTrxHashes = leanTrack.queueMotion(motionId);

        //assert trxHashes are queued in timelock
        for (uint256 i = 0; i < queuedTrxHashes.length; i++) {
            assertTrue(timelock.queuedRapidTransactions(queuedTrxHashes[i]));
        }

        // check for event
        vm.expectEmit(false, false, false, false);
        emit MotionCanceled(motionId);

        //execute
        hoax(knight);
        leanTrack.cancelMotion(motionId);

        //assert motion has been deleted
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, 0);

         //assert trxHashes are no longer queued in timelock
        for (uint256 i = 0; i < queuedTrxHashes.length; i++) {
            assertFalse(timelock.queuedRapidTransactions(queuedTrxHashes[i]));
        }
    }

    function testCanObjectToMotionReturnsTrue(address random, uint256 votingBalance) public {
        vm.assume(votingBalance >= QUORUM_AMOUNT && votingBalance < TOKEN_SUPPLY);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, 0);
        assertEq(motion.objectionsThreshold, QUORUM);
        deal(address(token), random, votingBalance);

        assertTrue(leanTrack.canObjectToMotion(motionId, random));
    }

    function testCanObjectToMotionReturnsFalseIfMotionDoesntExist(address random, uint256 votingBalance) public {
        vm.assume(votingBalance > 0 && votingBalance < QUORUM_AMOUNT);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);

        assertFalse(leanTrack.canObjectToMotion(motionId + 1, random));
    }

    function testCanObjectToMotionReturnsFalseIfMotionIsQueued(address random, uint256 votingBalance) public {
        vm.assume(votingBalance > 0 && votingBalance < QUORUM_AMOUNT);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        deal(address(token), random, votingBalance);

        // skip to time when motion is queued
        vm.warp(motion.timeForQueue);

        //execute
        leanTrack.queueMotion(motionId);

        assertFalse(leanTrack.canObjectToMotion(motionId, random));
    }

    function testCanObjectToMotionReturnsFalseIfMotionTimeForQueueHasPassed(address random, uint256 votingBalance) public {
        vm.assume(votingBalance > 0 && votingBalance < QUORUM_AMOUNT);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        deal(address(token), random, votingBalance);

        // skip to time when motion is queued
        vm.warp(motion.timeForQueue + 1);

        assertFalse(leanTrack.canObjectToMotion(motionId, random));
    }

    function testCanObjectToMotionReturnsFalseIfObjectorAlreadyObjected(address random, uint256 votingBalance) public {
        vm.assume(votingBalance > 0 && votingBalance < QUORUM_AMOUNT);
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, 0);
        assertEq(motion.objectionsThreshold, QUORUM);
        deal(address(token), random, votingBalance);
        uint256 votingBalanceForObjector = token.balanceOf(random);
        uint256 votingBalanceForObjectorPct = (votingBalanceForObjector * HUNDRED_PCT) / TOKEN_SUPPLY;

        // check for event
        vm.expectEmit(false, false, false, false);
        emit MotionObjected(motionId, random, votingBalanceForObjector, votingBalanceForObjector, votingBalanceForObjectorPct);

        //execute
        hoax(random); // has more than quorum
        leanTrack.objectToMotion(motionId); // should reject motion

        //assert motion objections were counted
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, votingBalanceForObjector);

        assertFalse(leanTrack.canObjectToMotion(motionId, random));
    }

    function testCanObjectToMotionReturnsFalseIfVotingBalanceIsZero(address random) public {
        vm.assume(!reserved[random]);
        // setup
        uint256 motionId;
        (motionId,) = _createMotion(1);
        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);
        assertEq(motion.objections, 0);
        assertEq(token.balanceOf(random), 0);

        assertFalse(leanTrack.canObjectToMotion(motionId, random));
    }


    function _createMotionTrxs(uint256 operations) private view returns (
        address[] memory targets, 
        uint256[] memory values, 
        string[] memory signatures, 
        bytes[] memory calldatas,
        bytes32[] memory trxHashes,
        uint256 totalAmount
    ) {
        targets = new address[](operations);
        values = new uint256[](operations);
        signatures = new string[](operations);
        calldatas = new bytes[](operations);
        trxHashes = new bytes32[](operations);
        uint256 eta = block.timestamp + factoryMotionDuration + leanTrackDelay;
        for (uint i = 0; i < operations; i++) {
            targets[i] = address(token);
            values[i] = 0;
            signatures[i] = "";
            // vary the amount of tokens to transfer to avoid hash collision
            calldatas[i] = abi.encodeWithSelector(IERC20.transfer.selector, grantee, transferAmount + i); 
            totalAmount += transferAmount + i;
            trxHashes[i] = keccak256(abi.encode(targets[i], values[i], signatures[i], calldatas[i], eta));
        }
        return (targets, values, signatures, calldatas, trxHashes, totalAmount);
    }

    function _createMotion(uint256 operations) private returns (uint256, bytes32[] memory) {
        address [] memory targets;
        uint256 [] memory values;
        string[] memory signatures;
        bytes[] memory calldatas;
        bytes32[] memory trxHashes;
        uint256 totalAmount;
        (targets, values, signatures, calldatas, trxHashes, totalAmount) = _createMotionTrxs(operations);

        hoax(factory);
        uint256 motionId = leanTrack.createMotion(targets, values, signatures, calldatas);

        return (motionId, trxHashes);
    }
}
