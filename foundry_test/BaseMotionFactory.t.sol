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
import {TransferMotionFactory} from "../src/factories/examples/TransferMotionFactory.sol";

import {MockLeanTrack, MotionArgs} from "./utils/MockLeanTrack.sol";

// these tests covers both the example TransferMotionFactory and the BaseMotionFactory contracts
contract BaseMotionFactoryTest is ExtendedTest {
    uint256 public constant DEFAULT_LIMIT = 1000;
    VyperDeployer private vyperDeployer = new VyperDeployer();
    DualTimelock private timelock;
    ERC20 private token;
    TransferMotionFactory private transferfactory;
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

        transferfactory = new TransferMotionFactory(address(leanTrack), address(admin));

        // set transfer limit
        hoax(admin);
        transferfactory.setTransferLimit(address(token), DEFAULT_LIMIT);
        // set authorized transfer motion creator
        hoax(admin);
        transferfactory.setAuthorized(authorized, true);

        // vm traces
        vm.label(address(transferfactory), "transferfactory");
        vm.label(address(leanTrack), "leanTrack");
        vm.label(address(govToken), "govToken");
        vm.label(address(token), "token");
    }
    function testSetup() public {
        assertEq(address(transferfactory.gov()), admin);
        assertEq(address(transferfactory.leanTrack()), address(leanTrack));

        assertEq(transferfactory.transferLimits(address(token)), DEFAULT_LIMIT);
        assertEq(transferfactory.authorized(authorized), true);
    }

    function testCreateTransferMotion() public {
        // create transfer motion
        hoax(authorized);
        uint256 motionId = transferfactory.createTransferMotion(address(token), grantee, 100);

        assertEq(motionId, 1);
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        string[] memory signatures = new string[](1);
        signatures[0] = "transfer(address,uint256)";
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encode(grantee, 100);
        
        // check lean track was called with expected params
        MotionArgs memory motionArgs = leanTrack.getMotionArgs(motionId);
        assertEq(motionArgs.id, motionId);
        assertEq(motionArgs.targets, targets);
        assertEq(motionArgs.calldatas[0], calldatas[0]);
        assertEq(motionArgs.signatures[0], signatures[0]);
        assertEq(motionArgs.values[0], values[0]);
    }

    function testCannotCreateMotionWithZeroAmount() public {
        vm.expectRevert("!amount");

        // create transfer motion
        hoax(authorized);
        transferfactory.createTransferMotion(address(token), grantee, 0);
    }

    function testOnlyAuthorizedCanCreateMotion() public {
        vm.expectRevert("!auth");

        // create transfer motion
        hoax(objectoor);
        transferfactory.createTransferMotion(address(token), grantee, 100);
    }

    function testRandomCanotCallSetAuthorized() public {
        vm.expectRevert();

        // set authorized
        hoax(objectoor);
        transferfactory.setAuthorized(objectoor, true);
    }


    function testCancelTransferMotion() public {
        // create transfer motion
        hoax(authorized);
        uint256 motionId = transferfactory.createTransferMotion(address(token), grantee, 100);

        assertEq(motionId, 1);
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        string[] memory signatures = new string[](1);
        signatures[0] = "transfer(address,uint256)";
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encode(grantee, 100);
        
        // check lean track was called with expected params
        assertEq(leanTrack.motions(motionId).id, motionId);
        MotionArgs memory motionArgs = leanTrack.getMotionArgs(motionId);
        assertEq(motionArgs.targets, targets);
        assertEq(motionArgs.calldatas[0], calldatas[0]);
        assertEq(motionArgs.signatures[0], signatures[0]);
        assertEq(motionArgs.values[0], values[0]);

        // cancel transfer motion
        hoax(authorized);
        transferfactory.cancelMotion(motionId);

        // check lean track motion id was deleted
        assertEq(leanTrack.motions(motionId).id, 0);
    }

}
