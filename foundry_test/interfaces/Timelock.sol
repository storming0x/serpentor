// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

struct Transaction {
    address target;
    uint256 amount;
    uint256 eta;
    string signature;
    bytes callData;
}

interface Timelock {
    function queen() external view returns (address);
    function pendingQueen() external view returns (address);
    function delay() external view returns (uint);
    function setDelay(uint256 newDelay) external;       
    function setPendingQueen(address pendingqueen) external;
    function GRACE_PERIOD() external view returns (uint);
    function acceptThrone() external;
    function queuedTransactions(bytes32 hash) external view returns (bool);
    function queueTransaction(Transaction calldata trx) external returns (bytes32);
    function cancelTransaction(Transaction calldata trx) external;
    function executeTransaction(Transaction calldata trx) external payable returns (bytes memory);
}