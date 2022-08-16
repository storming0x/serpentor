// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {SerpentorBravo} from "./interfaces/SerpentorBravo.sol";

contract SerpentorBravoTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    SerpentorBravo private serpentor;
  
    function setUp() public {
        serpentor = SerpentorBravo(vyperDeployer.deployContract("src/", "SerpentorBravo"));
        console.log("address for gov contract: ", address(serpentor));

        // add more labels to make your traces readable
        vm.label(address(serpentor), "SerpentorBravo");
    }

    function testSetup() public {
        assertNeq(address(serpentor), address(0));
    }
}
