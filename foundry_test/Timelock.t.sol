// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {Timelock} from "./interfaces/Timelock.sol";

contract TimelockTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    Timelock private timelock;

    function setUp() public {
        timelock = Timelock(vyperDeployer.deployContract("src/", "Timelock"));
        console.log("address for timelock: ", address(timelock));
    }

    function testSetup() public {
        assertNeq(address(timelock), address(0));
    }
}
