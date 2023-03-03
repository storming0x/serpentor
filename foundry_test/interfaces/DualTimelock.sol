// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

struct Transaction {
    address target;
    uint256 amount;
    uint256 eta;
    string signature;
    bytes callData;
}

interface DualTimelock {
    // compatible interface with other Timelocks
    function admin() external view returns (address);
    function pendingAdmin() external view returns (address);
    function delay() external view returns (uint);
    function setDelay(uint256 newDelay) external;       
    function setPendingAdmin(address pendingadmin) external;
    function GRACE_PERIOD() external view returns (uint);
    function acceptAdmin() external;
    function queuedTransactions(bytes32 hash) external view returns (bool);
    function queueTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) external returns (bytes32);
    function cancelTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) external;
    function executeTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) external payable returns (bytes memory);

    // DualTimelock specific functions
    function fastTrack() external view returns (address);
    function pendingFastTrack() external view returns (address);
    function fastTrackDelay() external view returns (uint);
    function setFastTrackDelay(uint256 newDelay) external;
    function acceptFastTrack() external;
    function setPendingFastTrack(address pendingFastTrack) external;
    function queuedFastTransactions(bytes32 hash) external view returns (bool);
    function queueFastTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) external returns (bytes32);
    function cancelFastTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) external;
    function executeFastTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) external payable returns (bytes memory);
}