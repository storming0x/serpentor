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
import {VaultOperationsMotionFactory} from "../src/factories/examples/VaultOperationsMotionFactory.sol";
import {MockVault as Vault} from "./utils/MockVault.sol";

import {
    LeanTrack, 
    Factory,
    Motion
} from "./interfaces/LeanTrack.sol";

// these tests covers  VaultsOperationFactory and the BaseMotionFactory contracts
contract VaultOperationsMotionFactoryTest is ExtendedTest {
    uint256 public constant QUORUM = 2000; // 20%
    VyperDeployer private vyperDeployer = new VyperDeployer();
    DualTimelock private timelock;
    ERC20 private token;
    VaultOperationsMotionFactory private factory;
    LeanTrack private leanTrack;
    GovToken private govToken;
    Vault private vault;

    uint256 public delay = 2 days;
    uint256 public leanTrackDelay = 60 seconds;
    uint256 public factoryMotionDuration = 2 minutes;

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

        factory = new VaultOperationsMotionFactory(address(leanTrack), address(admin));

        // set authorized vault operations motion creator
        hoax(admin);
        factory.setAuthorized(authorized, true);

         // setup factory
        hoax(admin);
        // short time duration for this factory since its only emergerncy functions
        leanTrack.addMotionFactory(address(factory), QUORUM, factoryMotionDuration);

        // add executor
        hoax(admin);
        leanTrack.addExecutor(address(knight));

        // setup vault
        vault = new Vault(address(timelock));

        // vm traces
        vm.label(address(timelock), "DualTimelock");
        vm.label(address(factory), "factory");
        vm.label(address(leanTrack), "leanTrack");
        vm.label(address(govToken), "govToken");
        vm.label(address(token), "token");
        vm.label(address(vault), "vault");
    }
    function testSetup() public {
        assertNeq(address(timelock), address(0));
        assertNeq(address(leanTrack), address(0));
        assertNeq(address(vault), address(0));

        assertEq(address(timelock.admin()), admin);
        assertEq(timelock.delay(), delay);
        assertEq(timelock.leanTrackDelay(), leanTrackDelay);
        assertEq(leanTrack.admin(), admin);
        assertEq(leanTrack.token(), address(token));
        assertTrue(leanTrack.executors(address(knight)));
        assertTrue(leanTrack.factories(address(factory)).isFactory);
        assertEq(leanTrack.factories(address(factory)).objectionsThreshold, QUORUM);
        assertEq(leanTrack.factories(address(factory)).motionDuration, factoryMotionDuration);
        assertEq(address(factory.gov()), admin);
        assertEq(address(factory.leanTrack()), address(leanTrack));

        assertEq(factory.authorized(authorized), true);
    }

    function testDisableDepositLimitInVault() public {
        // create motion to disable deposit limit in vault
        hoax(authorized);
        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);
        uint256 motionId = factory.disableDepositLimit(vaults);

        assertEq(motionId, 1);

        Motion memory motion = leanTrack.motions(motionId);
        assertEq(motion.id, motionId);

        vm.warp(motion.timeForQueue); //skip to eta

        // setup queue motion
        hoax(objectoor);
        leanTrack.queueMotion(motionId);

        motion = leanTrack.motions(motionId);
        assertTrue(motion.eta != 0);
        vm.warp(motion.eta); //skip to eta

        //execute
        hoax(knight); 
        leanTrack.enactMotion(motionId);

        //assert motion has been enacted
        motion = leanTrack.motions(motionId);
        assertEq(motion.id, 0);
        // check transaction was executed
        assertEq(vault.depositLimit(), 0);

    }

}
