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
    function leanTrack() external view returns (address);
    function pendingLeanTrack() external view returns (address);
    function leanTrackDelay() external view returns (uint);
    function setLeanTrackDelay(uint256 newDelay) external;
    function acceptLeanTrack() external;
    function setPendingLeanTrack(address pendingLeanTrack) external;
    function queuedRapidTransactions(bytes32 hash) external view returns (bool);
    function queueRapidTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) external returns (bytes32);
    function cancelRapidTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) external;
    function executeRapidTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) external payable returns (bytes memory);
}