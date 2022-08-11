// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface Token {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}