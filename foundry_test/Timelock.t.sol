// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {Timelock, Transaction} from "./interfaces/Timelock.sol";

contract TimelockTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    Timelock private timelock;
    address public admin = address(1);
    address public holder = address(2);
    address public grantee = address(3);

    uint public constant GRACE_PERIOD = 14 days;
    uint public constant MINIMUM_DELAY = 2 days;
    uint public constant MAXIMUM_DELAY = 30 days;
    uint256 public delay = 2 days;
    
    // events

    event NewDelay(uint256 newDelay);
    event NewAdmin(address indexed newAdmin);
    event QueueTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    event CancelTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    event ExecuteTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);

    function setUp() public {
        bytes memory args = abi.encode(admin, delay);
        timelock = Timelock(vyperDeployer.deployContract("src/", "Timelock", args));
        console.log("address for timelock: ", address(timelock));

        // vm traces
        vm.label(address(timelock), "Timelock");
    }

    function testSetup() public {
        assertNeq(address(timelock), address(0));
        assertEq(address(timelock.admin()), admin);
        assertEq(timelock.delay(), delay);
        assertEq(timelock.delay(), MINIMUM_DELAY);
    }

    function testRandomAcctCannotSetDelay(address random) public {
        vm.assume(random != address(timelock));
        vm.expectRevert("!Timelock");

        vm.prank(random);
        timelock.setDelay(5 days);
    }

    function testOnlySelfCanSetDelay(uint256 newDelay) public {
        vm.assume(delay >= MINIMUM_DELAY && delay <= MAXIMUM_DELAY);
        //setup
        //setup for event checks
        vm.expectEmit(false, false, false, false);
        emit NewDelay(newDelay);
        // execute
        vm.prank(address(timelock));
        timelock.setDelay(5 days);
        // asserts
        assertEq(timelock.delay(), 5 days);
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

    function testRandomAcctCannotTakeOverAdmin(address random) public {
        vm.assume(random != admin && random != address(0));
        // setup
        vm.expectRevert(bytes("!pendingAdmin"));
        // execute
        vm.prank(random);
        timelock.acceptAdmin();
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

    function testRandomAcctCannotQueueTrx(address random) public {
        vm.assume(random != admin);
        // setup
        vm.expectRevert(bytes("!admin"));

        // execute
        vm.prank(random);
        timelock.queueTransaction(address(timelock), 0, "", "", block.timestamp + 10 days);
    }

    function testQueueTrxEtaCannotBeInvalid() public {
        // setup
        vm.expectRevert(bytes("!eta"));
    
        uint256 badEta = block.timestamp;

        // execute
        vm.prank(address(admin));
        timelock.queueTransaction(address(timelock), 0, "", "", badEta);
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

    function testRandomAcctCannotCancelQueueTrx(address random) public {
        vm.assume(random != admin);
        // setup
        vm.expectRevert(bytes("!admin"));

        // execute
        vm.prank(address(0xABCD));
        timelock.cancelTransaction(address(timelock), 0, "", "", block.timestamp + 10 days);
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

    function testRandomAcctCantExecQueuedTrx(address random) public {
        vm.assume(random != admin);
        // setup
        vm.expectRevert(bytes("!admin"));

        // execute
        vm.prank(random);
        timelock.cancelTransaction(address(timelock), 0, "", "", block.timestamp + 10 days);
    }

    function testRandomAcctCannotExecQueuedTrx(address random) public {
        vm.assume(random != admin);
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
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));

        vm.expectRevert(bytes("!admin"));
        // execute
        vm.prank(random);
        timelock.executeTransaction(target, amount, signature, callData, eta);
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
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));

        skip(2 days); // short of ETA
        vm.expectRevert(bytes("!eta"));
        // execute
        vm.prank(address(admin));
        timelock.executeTransaction(target, amount, signature, callData, eta);
    }

    function testCannotExecQueuedTrxAfterGracePeriod(uint256 executionTime) public {
        uint256 eta = block.timestamp + delay + 2 days;
        uint256 gracePeriod = timelock.GRACE_PERIOD();
        vm.assume(executionTime > eta + gracePeriod && executionTime < type(uint128).max);
        // setup
        uint256 newDelay = 5 days;
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
        vm.prank(address(admin));
        bytes32 trxHash = timelock.queueTransaction(target, amount, signature, callData, eta);
        assertTrue(timelock.queuedTransactions(trxHash));
        skip(executionTime); // skip to time of execution passed gracePeriod
        vm.expectRevert(bytes("!staled_trx"));
        // execute
        vm.prank(address(admin));
        timelock.executeTransaction(target, amount, signature, callData, eta);
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
