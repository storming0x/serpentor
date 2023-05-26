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
import {BribesToSplitterMotionFactory} from "../src/factories/examples/BribesToSplitterMotionFactory.sol";

import {MockLeanTrack, MotionArgs} from "./utils/MockLeanTrack.sol";

// these tests covers both the example BribesToSplitter and the BaseMotionFactory contracts
contract BribesToSplitterMotionFactoryTest is ExtendedTest {
    address public immutable VOTER = 0xF147b8125d2ef93FB6965Db97D6746952a133934;
    address public immutable SPLITTER = 0x527e80008D212E2891C737Ba8a2768a7337D7Fd2;
    uint256 public constant DEFAULT_LIMIT = 1000;
    VyperDeployer private vyperDeployer = new VyperDeployer();
    DualTimelock private timelock;
    ERC20 private token;
    BribesToSplitterMotionFactory private factory;
    MockLeanTrack private leanTrack;
    GovToken private govToken;

    uint256 public delay = 2 days;
    uint256 public leanTrackDelay = 1 days;
    uint256 public factoryMotionDuration = 1 days;

    address public admin = address(1);
    address public authorized = address(2);
    address public objectoor = address(3);
    address public mediumVoter = address(4);
    address public whaleVoter1 = address(5);
    address public whaleVoter2 = address(6);
    address public knight = address(7);
    address public smallVoter = address(8);
    address public grantee = address(0xABCD);
    address public executor = address(7);

    event MotionCreated(
        address[] targets, 
        uint256[] values, 
        string[] signatures, 
        bytes[] calldatas
    );

    function setUp() public {
         // deploy token
        govToken = new GovToken(18);
        token = ERC20(govToken);

        // deploy mock lean track
        leanTrack = new MockLeanTrack();

        factory = new BribesToSplitterMotionFactory(address(leanTrack), address(admin));

        // set transfer limit
        hoax(admin);
        factory.setTransferLimit(address(token), DEFAULT_LIMIT);
        // set authorized transfer motion creator
        hoax(admin);
        factory.setAuthorized(authorized, true);

        // vm traces
        vm.label(address(factory), "factory");
        vm.label(address(leanTrack), "leanTrack");
        vm.label(address(govToken), "govToken");
        vm.label(address(token), "token");
    }
    function testSetup() public {
        assertEq(address(factory.gov()), admin);
        assertEq(address(factory.leanTrack()), address(leanTrack));

        assertEq(factory.transferLimits(address(token)), DEFAULT_LIMIT);
        assertEq(factory.authorized(authorized), true);
    }

    function testCreateTransferMotion() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;

        // create transfer motion
        hoax(authorized);
        uint256 motionId = factory.createBribesTransferMotion(tokens, amounts);

        assertEq(motionId, 1);
        address[] memory targets = new address[](1);
        targets[0] = VOTER;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        string[] memory signatures = new string[](1);
        bytes memory calldataForTransfer = abi.encodeWithSignature("transfer(address,uint256)", SPLITTER, 100);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("execute(address,uint256,bytes)", address(token), 0, calldataForTransfer);
        
        // check lean track was called with expected params
        MotionArgs memory motionArgs = leanTrack.getMotionArgs(motionId);
        assertEq(motionArgs.id, motionId);
        assertEq(motionArgs.targets, targets);
        assertEq(motionArgs.calldatas[0], calldatas[0]);
        assertEq(motionArgs.signatures[0], signatures[0]);
        assertEq(motionArgs.values[0], values[0]);
    }

}
