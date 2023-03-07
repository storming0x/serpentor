// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/ERC20.sol";

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {DualTimelock, Transaction} from "./interfaces/DualTimelock.sol";
import {GovToken} from "./utils/GovToken.sol";

contract DualTimelockTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    DualTimelock private timelock;
    ERC20 private token;
    address public admin = address(1);
    address public holder = address(2);
    address public grantee = address(3);
    address public fastTrack = address(4);

    uint public constant GRACE_PERIOD = 14 days;
    uint public constant MINIMUM_DELAY = 2 days;
    uint public constant MAXIMUM_DELAY = 30 days;
    uint256 public delay = 2 days;
    uint256 public fastTrackDelay = 1 days;
    
    // events

    event NewDelay(uint256 newDelay);
    event NewFastTrackDelay(uint256 newDelay);
    event NewAdmin(address indexed newAdmin);
    event NewPendingAdmin(address indexed newPendingAdmin);
    event NewFastTrack(address indexed newFastTrack);
    event NewPendingFastTrack(address indexed newPendingFastTrack);
    event QueueTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    event CancelTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    event ExecuteTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    event QueueFastTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    event CancelFastTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    event ExecuteFastTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);

    function setUp() public {
        bytes memory args = abi.encode(admin, fastTrack, delay, fastTrackDelay);
        timelock = DualTimelock(vyperDeployer.deployContract("src/", "DualTimelock", args));
        console.log("address for DualTimelock: ", address(timelock));

        // deploy token
        token = ERC20(new GovToken(18));
        console.log("address for GovToken: ", address(token));

        // vm traces
        vm.label(address(timelock), "DualTimelock");
        vm.label(address(token), "Token");

        deal(address(token), address(timelock), 1000e18);
    }

    function testSetup() public {
        assertNeq(address(timelock), address(0));
        assertEq(address(timelock.admin()), admin);
        assertEq(address(timelock.fastTrack()), fastTrack);
        assertEq(timelock.delay(), delay);
        assertEq(timelock.delay(), MINIMUM_DELAY);
        assertEq(timelock.fastTrackDelay(), fastTrackDelay);

        assertEq(token.balanceOf(address(timelock)), 1000e18);
    }

    function testRandomAcctCannotSetDelay(address random) public {
        vm.assume(random != address(timelock));
        vm.expectRevert("!Timelock");

        vm.prank(random);
        timelock.setDelay(5 days);
    }

    function testRandomAcctCannotSetFastTrackDelay(address random) public {
        vm.assume(random != address(timelock));
        vm.expectRevert("!Timelock");

        vm.prank(random);
        timelock.setFastTrackDelay(0 days);
    }

    function testOnlySelfCanSetDelay(uint256 newDelay) public {
        vm.assume(newDelay >= MINIMUM_DELAY && newDelay <= MAXIMUM_DELAY);
        //setup
        //setup for event checks
        vm.expectEmit(false, false, false, false);
        emit NewDelay(newDelay);
        // execute
        vm.prank(address(timelock));
        timelock.setDelay(newDelay);
        // asserts
        assertEq(timelock.delay(), newDelay);
    }

    function testOnlySelfCanSetFastTrackDelay(uint256 newDelay) public {
        vm.assume(newDelay >= 0 && newDelay < MINIMUM_DELAY);
        //setup
        //setup for event checks
        vm.expectEmit(false, false, false, false);
        emit NewFastTrackDelay(newDelay);
        // execute
        vm.prank(address(timelock));
        timelock.setFastTrackDelay(newDelay);
        // asserts
        assertEq(timelock.fastTrackDelay(), newDelay);
    }

    function testSetFastTrackDelayCannotBeGreaterThanDelay(uint256 newDelay) public {
        uint currentDelay = timelock.delay();
        vm.assume(newDelay > currentDelay);
        //setup
        vm.expectRevert("!fastTrackDelay < delay");
        // execute
        vm.prank(address(timelock));
        timelock.setFastTrackDelay(newDelay);
    }
    

    function testDelayCannotBeBelowMinimum(uint256 newDelay) public {
        vm.assume(newDelay < MINIMUM_DELAY);
        // setup
        vm.expectRevert("!MINIMUM_DELAY");
        // execute
        vm.prank(address(timelock));
        // delay minimum in contract is 2 days
        timelock.setDelay(newDelay);
    }

    function testDelayCannotBeAboveMax(uint256 newDelay) public {
        vm.assume(newDelay > MAXIMUM_DELAY && newDelay <= 1000 days);
        // setup
        vm.expectRevert("!MAXIMUM_DELAY");
        // execute
        vm.prank(address(timelock));
        // delay maximum in contract is 30 days
        timelock.setDelay(newDelay);
    }

    function testRandomAcctCannotSetNewAdmin(address random) public {
        vm.assume(random != address(timelock));
        // setup
        vm.expectRevert(bytes("!Timelock"));
        // execute
        vm.prank(random);
        timelock.setPendingAdmin(random);
    }

    function testRandomAcctCannotSetNewFastTrack(address random) public {
        vm.assume(random != address(timelock));
        // setup
        vm.expectRevert(bytes("!Timelock"));
        // execute
        vm.prank(random);
        timelock.setPendingFastTrack(random);
    }

    function testRandomAcctCannotTakeOverAdmin(address random) public {
        vm.assume(random != admin && random != address(0));
        // setup
        vm.expectRevert(bytes("!pendingAdmin"));
        // execute
        vm.prank(random);
        timelock.acceptAdmin();
    }

    function testRandomAcctCannotTakeOverFastTrack(address random) public {
        vm.assume(random != fastTrack && random != address(0));
        // setup
        vm.expectRevert(bytes("!pendingFastTrack"));
        // execute
        vm.prank(random);
        timelock.acceptFastTrack();
    }

    function testOnlyPendingAdminCanAcceptAdmin() public {
        // setup
        address futureAdmin = address(0xBEEF);
        // setup pendingAdmin
        vm.prank(address(timelock));
        timelock.setPendingAdmin(futureAdmin);
        assertEq(timelock.pendingAdmin(), futureAdmin);
        //setup for event checks
        vm.expectEmit(true, false, false, false);
        emit NewAdmin(futureAdmin);

        // execute
        vm.prank(futureAdmin);
        timelock.acceptAdmin();

        // asserts
        assertEq(timelock.admin(), futureAdmin);
        assertEq(timelock.pendingAdmin(), address(0));
    } 

    function testOnlyPendingFastTrackCanCallAcceptFastTrack() public {
        // setup
        address futureFastTrack = address(0xBEEF);
        // setup pendingAdmin
        vm.prank(address(timelock));
        timelock.setPendingFastTrack(futureFastTrack);
        assertEq(timelock.pendingFastTrack(), futureFastTrack);
        //setup for event checks
        vm.expectEmit(true, false, false, false);
        emit NewFastTrack(futureFastTrack);

        // execute
        vm.prank(futureFastTrack);
        timelock.acceptFastTrack();

        // asserts
        assertEq(timelock.fastTrack(), futureFastTrack);
        assertEq(timelock.pendingFastTrack(), address(0));
    } 

    function testRandomAcctCannotQueueTrx(address random) public {
        vm.assume(random != admin);
        // setup
        vm.expectRevert(bytes("!admin"));

        // execute
        vm.prank(random);
        timelock.queueTransaction(address(timelock), 0, "", "", block.timestamp + 10 days);
    }

    function testRandomAcctCannotQueueFastTrx(address random) public {
        vm.assume(random != fastTrack);
        // setup
        vm.expectRevert(bytes("!fastTrack"));

        // execute
        vm.prank(random);
        timelock.queueFastTransaction(address(timelock), 0, "", "", block.timestamp + 10 days);
    }

    function testQueueTrxEtaCannotBeInvalid() public {
        // setup
        vm.expectRevert(bytes("!eta"));
    
        uint256 badEta = block.timestamp;

        // execute
        vm.prank(address(admin));
        timelock.queueTransaction(address(timelock), 0, "", "", badEta);
    }

    function testQueueFastTrxEtaCannotBeInvalid() public {
        // setup
        vm.expectRevert(bytes("!eta"));
    
        uint256 badEta = block.timestamp;

        // execute
        vm.prank(address(fastTrack));
        timelock.queueFastTransaction(address(grantee), 0, "", "", badEta);
    }

    function testShouldQueueTrx() public {
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(DualTimelock.setDelay.selector, newDelay);
        uint256 amount = 0;
        string memory signature = "";
        bytes32 expectedTrxHash;
        Transaction memory testTrx;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit QueueTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        // asserts
        assertEq(expectedTrxHash, trxHash);
        assertTrue(timelock.queuedTransactions(trxHash));
    }

    function testShouldQueueFastTrx() public {
        // setup
        uint256 eta = block.timestamp + 1 days;
        address target = address(token);
        bytes memory callData = abi.encodeWithSelector(ERC20.transfer.selector, grantee, 1000);
        uint256 amount = 0;
        string memory signature = "";
        bytes32 expectedTrxHash;
        Transaction memory testTrx;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit QueueFastTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(fastTrack));
        bytes32 trxHash = timelock.queueFastTransaction(target, amount, signature, callData, eta);
        // asserts
        assertEq(expectedTrxHash, trxHash);
        assertTrue(timelock.queuedFastTransactions(trxHash));
    }

    function testFastTrackCannotTargetTimelock() public {
        // setup
        uint256 eta = block.timestamp + 1 days;
        // cannot call timelock
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(DualTimelock.setDelay.selector, 5 days);
        uint256 amount = 0;
        string memory signature = "";
        bytes32 expectedTrxHash;
        Transaction memory testTrx;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        //setup for expect revert
        vm.expectRevert(bytes("!self"));

        // execute
        vm.prank(address(fastTrack));
        timelock.queueFastTransaction(target, amount, signature, callData, eta);
    }

    function testRandomAcctCannotCancelQueueTrx(address random) public {
        vm.assume(random != admin);
        // setup
        vm.expectRevert(bytes("!admin"));

        // execute
        vm.prank(address(0xABCD));
        timelock.cancelTransaction(address(timelock), 0, "", "", block.timestamp + 10 days);
    }

    function testRandomAcctCannotCancelFastQueueTrx(address random) public {
        vm.assume(random != fastTrack);
        // setup
        vm.expectRevert(bytes("!fastTrack"));

        // execute
        vm.prank(address(0xABCD));
        timelock.cancelFastTransaction(address(token), 0, "", "", block.timestamp + 1 days);
     }

     function testShouldCancelQueuedTrx() public {
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(DualTimelock.setDelay.selector, newDelay);
        uint256 amount = 0;
        string memory signature = "";
        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );

        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));

        //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit CancelTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(admin));
        timelock.cancelTransaction(target, amount, signature, callData, eta);

        // asserts
        assertFalse(timelock.queuedTransactions(trxHash));
    }

    function testShouldCancelFastQueuedTrx() public {
        // setup
        uint256 eta = block.timestamp + 1 days;
        address target = address(token);
        bytes memory callData = abi.encodeWithSelector(ERC20.transfer.selector, grantee, 1000);
        uint256 amount = 0;
        string memory signature = "";
        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );

        vm.prank(address(fastTrack));
        bytes32 trxHash = timelock.queueFastTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedFastTransactions(trxHash));

        //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit CancelFastTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(fastTrack));
        timelock.cancelFastTransaction(target, amount, signature, callData, eta);

        // asserts
        assertFalse(timelock.queuedFastTransactions(trxHash));
    }

    function testRandomAcctCannotExecQueuedTrx(address random) public {
        vm.assume(random != admin);
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(DualTimelock.setDelay.selector, newDelay);
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));

        vm.expectRevert(bytes("!admin"));
        // execute
        vm.prank(random);
        timelock.executeTransaction(target, amount, signature, callData, eta);
    }

    function testRandomAcctCannotExecQueuedFastTrx(address random) public {
        vm.assume(random != fastTrack);
        // setup
        uint256 eta = block.timestamp + 1 days;
        address target = address(token);
        bytes memory callData = abi.encodeWithSelector(ERC20.transfer.selector, grantee, 1000);
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(fastTrack));
        bytes32 trxHash = timelock.queueFastTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedFastTransactions(trxHash));

        vm.expectRevert(bytes("!fastTrack"));
        // execute
        vm.prank(random);
        timelock.executeFastTransaction(target, amount, signature, callData, eta);
    } 

    function testCannotExecNonExistingTrx() public {
        // setup
         // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(DualTimelock.setDelay.selector, newDelay);
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory queuedTransaction;
        bytes32 expectedTrxHash;
        (queuedTransaction, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));

        Transaction memory wrongTrx;
        bytes32 wrongTrxHash;
        (wrongTrx, wrongTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            "",
            eta
        );

        vm.expectRevert(bytes("!queued_trx"));
        // execute
        vm.prank(address(admin));
        timelock.executeTransaction(target, amount, signature, "", eta);
    }

    function testCannotExecNonExistingFastTrx() public {
        // setup
        uint256 eta = block.timestamp + 1 days;
        address target = address(token);
        bytes memory callData = abi.encodeWithSelector(ERC20.transfer.selector, grantee, 1000);
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory queuedTransaction;
        bytes32 expectedTrxHash;
        (queuedTransaction, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(fastTrack));
        bytes32 trxHash = timelock.queueFastTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedFastTransactions(trxHash));

        Transaction memory wrongTrx;
        bytes32 wrongTrxHash;
        (wrongTrx, wrongTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            "",
            eta
        );

        vm.expectRevert(bytes("!queued_trx"));
        // execute
        vm.prank(address(fastTrack));
        timelock.executeFastTransaction(target, amount, signature, "", eta);
    }

    function testCannotExecQueuedTrxBeforeETA() public {
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(DualTimelock.setDelay.selector, newDelay);
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));

        skip(2 days); // short of ETA
        vm.expectRevert(bytes("!eta"));
        // execute
        vm.prank(address(admin));
        timelock.executeTransaction(target, amount, signature, callData, eta);
    }

    function testCannotExecQueuedFastTrxBeforeETA() public {
        // setup
        uint256 eta = block.timestamp + 1 days;
        address target = address(token);
        bytes memory callData = abi.encodeWithSelector(ERC20.transfer.selector, grantee, 1000);
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(fastTrack));
        bytes32 trxHash = timelock.queueFastTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedFastTransactions(trxHash));

        skip(12 hours); // short of ETA
        vm.expectRevert(bytes("!eta"));
        // execute
        vm.prank(address(fastTrack));
        timelock.executeFastTransaction(target, amount, signature, callData, eta);
    }

    function testCannotExecQueuedTrxAfterGracePeriod(uint256 executionTime) public {
        uint256 eta = block.timestamp + delay + 2 days;
        uint256 gracePeriod = timelock.GRACE_PERIOD();
        vm.assume(executionTime > eta + gracePeriod && executionTime < type(uint128).max);
        // setup
        uint256 newDelay = 5 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(DualTimelock.setDelay.selector, newDelay);
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));
        skip(executionTime); // skip to time of execution passed gracePeriod
        vm.expectRevert(bytes("!staled_trx"));
        // execute
        vm.prank(address(admin));
        timelock.executeTransaction(target, amount, signature, callData, eta);
    }

    function testCannotExecQueuedFastTrxAfterGracePeriod(uint256 executionTime) public {
        uint256 eta = block.timestamp + 1 days;
        uint256 gracePeriod = timelock.GRACE_PERIOD();
        vm.assume(executionTime > eta + gracePeriod && executionTime < type(uint128).max);
        // setup
        address target = address(token);
        bytes memory callData = abi.encodeWithSelector(ERC20.transfer.selector, grantee, 1000);
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(fastTrack));
        bytes32 trxHash = timelock.queueFastTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedFastTransactions(trxHash));
        skip(executionTime); // skip to time of execution passed gracePeriod
        vm.expectRevert(bytes("!staled_trx"));
        // execute
        vm.prank(address(fastTrack));
        timelock.executeFastTransaction(target, amount, signature, callData, eta);
    }

        function testCannotExecFastTrxInIncorrectQueue() public {
        // setup
        address target = address(token);
        bytes memory callData = abi.encodeWithSelector(ERC20.transfer.selector, grantee, 1000);
        uint256 amount = 0;
        string memory signature = "";
        uint256 eta = block.timestamp + delay;

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));
        skip(eta + 1); // 1 pass eta
        
        vm.expectRevert(bytes("!queued_trx"));
        // execute
        vm.prank(address(fastTrack));
        timelock.executeFastTransaction(target, amount, signature, callData, eta);
    }


    function testShouldExecQueuedTrxCorrectly() public {
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(DualTimelock.setDelay.selector, newDelay);
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));
        skip(eta + 1); // 1 pass eta
         //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit ExecuteTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(admin));
        bytes memory response = timelock.executeTransaction(target, amount, signature, callData, eta);

        // asserts
        assertEq(string(response), string(""));
        assertEq(timelock.delay(), newDelay);
    }

    function testShouldExecQueuedFastTrxCorrectly() public {
        // setup
        uint256 eta = block.timestamp + 1 days;
        address target = address(token);
        bytes memory callData = abi.encodeWithSelector(ERC20.transfer.selector, grantee, 1000);
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(fastTrack));
        bytes32 trxHash = timelock.queueFastTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedFastTransactions(trxHash));
        skip(eta + 1); // 1 pass eta
         //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit ExecuteFastTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(fastTrack));
        timelock.executeFastTransaction(target, amount, signature, callData, eta);

        // asserts
        assertEq(token.balanceOf(grantee), 1000);
    }

    function testShouldExecQueuedTrxWithSignatureCorrectly() public {
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encode(newDelay);
        uint256 amount = 0;
        string memory signature = "setDelay(uint256)";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));
        skip(eta + 1); // 1 pass eta
         //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit ExecuteTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(admin));
        bytes memory response = timelock.executeTransaction(target, amount, signature, callData, eta);

        // asserts
        assertEq(string(response), string(""));
        assertEq(timelock.delay(), newDelay);
    }

    function testShouldExecQueuedFastTrxWithSignatureCorrectly() public {
        // setup
        uint256 eta = block.timestamp + 1 days;
        address target = address(token);
        bytes memory callData = abi.encode(grantee, 1000);
        uint256 amount = 0;
        string memory signature = "transfer(address,uint256)";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(fastTrack));
        bytes32 trxHash = timelock.queueFastTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedFastTransactions(trxHash));
        skip(eta + 1); // 1 pass eta
         //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit ExecuteFastTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(fastTrack));
        timelock.executeFastTransaction(target, amount, signature, callData, eta);

        // asserts
        assertEq(token.balanceOf(grantee), 1000);
    }

    function testShouldExecQueuedTrxWithTimelockEthTransferCorrectly() public {
        // setup
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(grantee);
        bytes memory callData;
        uint256 amount = 10 ether;
        string memory signature = "";
        assertEq(grantee.balance, 0);

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));
        skip(eta + 1); // 1 pass 
        deal(address(timelock), 11 ether);

         //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit ExecuteTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        hoax(address(admin), 1 ether);
        timelock.executeTransaction(target, amount, signature, callData, eta);

        // asserts
        assertEq(grantee.balance, amount);
        assertEq(address(timelock).balance, 1 ether);
    }

    function testShouldExecQueuedFastTrxWithTimelockEthTransferCorrectly() public {
        // setup
        uint256 eta = block.timestamp + 1 days;
        address target = address(grantee);
        bytes memory callData;
        uint256 amount = 10 ether;
        string memory signature = "";
        assertEq(grantee.balance, 0);

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(fastTrack));
        bytes32 trxHash = timelock.queueFastTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedFastTransactions(trxHash));
        skip(eta + 1); // 1 pass 
        deal(address(timelock), 11 ether);

         //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit ExecuteFastTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        hoax(address(fastTrack), 1 ether);
        timelock.executeFastTransaction(target, amount, signature, callData, eta);

        // asserts
        assertEq(grantee.balance, amount);
        assertEq(address(timelock).balance, 1 ether);
    }

    function testShouldExecQueuedTrxWithCallerEthTransferCorrectly() public {
        // setup
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(grantee);
        bytes memory callData;
        uint256 amount = 10 ether;
        string memory signature = "";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));
        skip(eta + 1); // 1 pass
        assertEq(address(timelock).balance, 0);
      
        //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit ExecuteTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        hoax(address(admin), 10 ether);
        timelock.executeTransaction{value: amount}(target, amount, signature, callData, eta);

        // asserts
        assertEq(grantee.balance, amount);
        assertEq(address(timelock).balance, 0);
    }

    function testShouldExecQueuedFastTrxWithCallerEthTransferCorrectly() public {
        // setup
        uint256 eta = block.timestamp + 1 days;
        address target = address(grantee);
        bytes memory callData;
        uint256 amount = 10 ether;
        string memory signature = "";

        Transaction memory testTrx;
        bytes32 expectedTrxHash;
        (testTrx, expectedTrxHash) =_getTransactionAndHash(
            target,
            amount,
            signature,
            callData,
            eta
        );
        vm.prank(address(fastTrack));
        bytes32 trxHash = timelock.queueFastTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedFastTransactions(trxHash));
        skip(eta + 1); // 1 pass
        assertEq(address(timelock).balance, 0);
      
        //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit ExecuteFastTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        hoax(address(fastTrack), 10 ether);
        timelock.executeFastTransaction{value: amount}(target, amount, signature, callData, eta);

        // asserts
        assertEq(grantee.balance, amount);
        assertEq(address(timelock).balance, 0);
    }

    function testTimelockCanReceiveEther() public {
        // setup eth balance
        uint256 amount = 10 ether;
        deal(address(this), 100 ether);
        assertEq(address(timelock).balance, 0 ether);

        payable(address(timelock)).transfer(amount);

        assertEq(address(timelock).balance, amount);
    }


    function _getTransactionAndHash(
        address target, 
        uint256 amount, 
        string memory signature, 
        bytes memory callData, 
        uint eta
    ) internal pure returns (Transaction memory, bytes32) {
        Transaction memory testTrx = Transaction({
            target: target,
            amount: amount,
            eta: eta,
            signature: signature,
            callData: callData
        });

        bytes32 trxHash = keccak256(abi.encode(target, amount, signature, callData, eta));

        return (testTrx, trxHash);
    }

}
