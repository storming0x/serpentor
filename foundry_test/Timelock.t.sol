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
        uint256 eta = block.timestamp + delay + 2 days;
        address target = address(timelock);
        bytes memory callData = abi.encodeWithSelector(Timelock.setDelay.selector, address(0xBEEF));
        uint256 amount = 0;
        string memory signature = "";

        Transaction memory testTrx = Transaction({
            target: target,
            amount: amount,
            eta: eta,
            signature: signature,
            callData: callData
        });

        bytes32 expectedTrxHash = keccak256(abi.encode(target, amount, signature, callData, eta));
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

}
