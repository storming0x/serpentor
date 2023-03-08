// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

interface FastTrack {
    // view functions
    function admin() external view returns (address);
    function pendingAdmin() external view returns (address);
    function token() external view returns (address);

    // non-view functions
    function createMotion(address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas) external returns (uint256);
}
