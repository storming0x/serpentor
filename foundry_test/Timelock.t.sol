// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {Timelock, Transaction} from "./interfaces/Timelock.sol";

contract TimelockTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    Timelock private timelock;
    address public queen = address(1);
    uint public constant GRACE_PERIOD = 14 days;
    uint public constant MINIMUM_DELAY = 2 days;
    uint public constant MAXIMUM_DELAY = 30 days;
    uint256 public delay = 2 days;
    
    // events

    event NewDelay(uint256 newDelay);
    event NewQueen(address indexed newQueen);
    event QueueTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    event CancelTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    event ExecuteTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);

    function setUp() public {
        bytes memory args = abi.encode(queen, delay);
        timelock = Timelock(vyperDeployer.deployContract("src/", "Timelock", args));
        console.log("address for timelock: ", address(timelock));

        // vm traces
        vm.label(address(timelock), "Timelock");
    }

    function testSetup() public {
        assertNeq(address(timelock), address(0));
        assertEq(address(timelock.queen()), queen);
        assertEq(timelock.delay(), delay);
        assertEq(timelock.delay(), 2 days);
    }

    function testRandomAcctCannotSetDelay() public {
        vm.expectRevert("!Timelock");

        vm.prank(address(0xABCD));
        timelock.setDelay(5 days);
    }

    function testOnlySelfCanSetDelay() public {
        //setup
        uint256 newDelay = 5 days;
        //setup for event checks
        vm.expectEmit(false, false, false, false);
        emit NewDelay(newDelay);
        // execute
        vm.prank(address(timelock));
        timelock.setDelay(5 days);
        // asserts
        assertEq(timelock.delay(), 5 days);
    }

    function testDelayCannotBeBelowMinimum() public {
        // setup
        vm.expectRevert("!MINIMUM_DELAY");
        // execute
        vm.prank(address(timelock));
        // delay minimum in contract is 2 days
        timelock.setDelay(1 days);
    }

    function testDelayCannotBeAboveMax() public {
        // setup
        vm.expectRevert("!MAXIMUM_DELAY");
        // execute
        vm.prank(address(timelock));
        // delay minimum in contract is 2 days
        timelock.setDelay(31 days);
    }

    function testRandomAcctCannotSetNewQueen() public {
        // setup
        vm.expectRevert(bytes("!Timelock"));
        // execute
        vm.prank(address(0xABCD));
        timelock.setPendingQueen(address(0xABCD));
    }

    function testRandomAcctCannotTakeOverThrone() public {
        // setup
        vm.expectRevert(bytes("!pendingQueen"));
        // execute
        vm.prank(address(0xABCD));
        timelock.acceptThrone();
    }

    function testOnlyPendingQueenCanAcceptThrone() public {
        // setup
        address futureQueen = address(0xBEEF);
        // setup pendingQueen
        vm.prank(address(timelock));
        timelock.setPendingQueen(futureQueen);
        assertEq(timelock.pendingQueen(), futureQueen);
        //setup for event checks
        vm.expectEmit(true, false, false, false);
        emit NewQueen(futureQueen);

        // execute
        vm.prank(futureQueen);
        timelock.acceptThrone();

        // asserts
        assertEq(timelock.queen(), futureQueen);
        assertEq(timelock.pendingQueen(), address(0));
    } 

    function testRandomAcctCannotQueueTrx() public {
        // setup
        vm.expectRevert(bytes("!queen"));

        Transaction memory emptyTrx = Transaction({
            target: address(timelock),
            amount: 0,
            eta: block.timestamp + 10 days,
            signature: "",
            callData: ""
        });

        // execute
        vm.prank(address(0xABCD));
        timelock.queueTransaction(emptyTrx);
    }

    function testQueueTrxEtaCannotBeInvalid() public {
        // setup
        vm.expectRevert(bytes("!eta"));
    
        uint256 badEta = block.timestamp;
        Transaction memory emptyTrx = Transaction({
            target: address(timelock),
            amount: 0,
            eta: badEta,
            signature: "",
            callData: ""
        });

        // execute
        vm.prank(address(queen));
        timelock.queueTransaction(emptyTrx);
    }

    function testShouldQueueTrx() public {
        // setup
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(Timelock.setDelay.selector, newDelay);
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
        //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit QueueTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(queen));
        bytes32 trxHash = timelock.queueTransaction(testTrx);
        // asserts
        assertEq(expectedTrxHash, trxHash);
        assertTrue(timelock.queuedTransactions(trxHash));
    }

    function testRandomAcctCannotCancelQueueTrx() public {
        // setup
        vm.expectRevert(bytes("!queen"));

        Transaction memory emptyTrx = Transaction({
            target: address(timelock),
            amount: 0,
            eta: block.timestamp + 10 days,
            signature: "",
            callData: ""
        });

        // execute
        vm.prank(address(0xABCD));
        timelock.cancelTransaction(emptyTrx);
    }

     function testShouldCancelQueuedTrx() public {
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(Timelock.setDelay.selector, newDelay);
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

        vm.prank(address(queen));
        bytes32 trxHash = timelock.queueTransaction(testTrx);
        assertTrue(timelock.queuedTransactions(trxHash));

        //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit CancelTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(queen));
        timelock.cancelTransaction(testTrx);

        // asserts
        assertFalse(timelock.queuedTransactions(trxHash));
    }

    function testRandomAcctCantExecQueuedTrx() public {
        // setup
        vm.expectRevert(bytes("!queen"));

        Transaction memory emptyTrx = Transaction({
            target: address(timelock),
            amount: 0,
            eta: block.timestamp + 10 days,
            signature: "",
            callData: ""
        });

        // execute
        vm.prank(address(0xABCD));
        timelock.cancelTransaction(emptyTrx);
    }

    function testRandomAcctCannotExecQueuedTrx() public {
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(Timelock.setDelay.selector, newDelay);
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
        vm.prank(address(queen));
        bytes32 trxHash = timelock.queueTransaction(testTrx);
        assertTrue(timelock.queuedTransactions(trxHash));

        vm.expectRevert(bytes("!queen"));
        // execute
        vm.prank(address(0xABCD));
        timelock.executeTransaction(testTrx);
    }

    function testCannotExecNonExistingTrx() public {
        // setup
         // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(Timelock.setDelay.selector, newDelay);
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
        vm.prank(address(queen));
        bytes32 trxHash = timelock.queueTransaction(queuedTransaction);
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
        vm.prank(address(queen));
        timelock.executeTransaction(wrongTrx);
    }

    function testCannotExecQueuedTrxBeforeETA() public {
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(Timelock.setDelay.selector, newDelay);
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
        vm.prank(address(queen));
        bytes32 trxHash = timelock.queueTransaction(testTrx);
        assertTrue(timelock.queuedTransactions(trxHash));

        skip(2 days); // short of ETA
        vm.expectRevert(bytes("!eta"));
        // execute
        vm.prank(address(queen));
        timelock.executeTransaction(testTrx);
    }

    function testCannotExecQueuedTrxAfterGracePeriod() public {
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(Timelock.setDelay.selector, newDelay);
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
        vm.prank(address(queen));
        bytes32 trxHash = timelock.queueTransaction(testTrx);
        assertTrue(timelock.queuedTransactions(trxHash));
        uint256 gracePeriod = timelock.GRACE_PERIOD();

        skip(eta + gracePeriod + 1); // 1 pass eta grace period
        vm.expectRevert(bytes("!staled_trx"));
        // execute
        vm.prank(address(queen));
        timelock.executeTransaction(testTrx);
    }


    function testShouldExecQueuedTrxCorrectly() public {
        // setup
        uint256 newDelay = 5 days;
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(Timelock.setDelay.selector, newDelay);
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
        vm.prank(address(queen));
        bytes32 trxHash = timelock.queueTransaction(testTrx);
        assertTrue(timelock.queuedTransactions(trxHash));
        skip(eta + 1); // 1 pass eta
         //setup for event checks
        vm.expectEmit(true, true, false, false);
        emit ExecuteTransaction(expectedTrxHash, target, amount, signature, callData, eta);

        // execute
        vm.prank(address(queen));
        bytes memory executedCalldata = timelock.executeTransaction(testTrx);

        // asserts
        assertEq(executedCalldata, callData);
        assertEq(timelock.delay(), newDelay);
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
