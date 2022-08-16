// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {Timelock} from "./interfaces/Timelock.sol";

contract TimelockTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    Timelock private timelock;
    address public king = address(1);
    uint256 public delay = 2 days;

    function setUp() public {
        bytes memory args = abi.encode(king, delay);
        timelock = Timelock(vyperDeployer.deployContract("src/", "Timelock", args));
        console.log("address for timelock: ", address(timelock));

        // add more labels to make your traces readable
        vm.label(address(timelock), "Timelock");
    }

    function testSetup() public {
        assertNeq(address(timelock), address(0));
    }
}
