// SPDX-License-Identifier: WTFPL
pragma solidity ^0.8.15;

import {ExtendedTest} from "./utils/ExtendedTest.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";

import {console} from "forge-std/console.sol";
import {Token} from "./interfaces/Token.sol";

contract TokenTest is ExtendedTest {
    VyperDeployer private vyperDeployer = new VyperDeployer();
    Token private token;

    function setUp() public {
        token = Token(
            vyperDeployer.deployContract("src/test/", "Token")
        );
        console.log("address for token: ", address(token));
    }

    function testSetup() public {
       assertNeq(address(token), address(0));
       assertEq(token.name(), "Test Token");
       assertEq(token.symbol(), "TEST");
    }
}