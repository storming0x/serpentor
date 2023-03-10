// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

// struct for motion factory settings
struct Factory {
    uint256 objectionsThreshold;
    uint256 motionDuration;
    bool isFactory;
}
// struct for a motion
struct Motion {
    uint256 id;
    address proposer;
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;
    uint256 timeForQueue;
    uint256 snapshotBlock;
    uint256 objections;
    uint256 objectionsThreshold;
}

interface FastTrack {
    // view functions
    function admin() external view returns (address);
    function pendingAdmin() external view returns (address);
    function token() external view returns (address);
    function factories(address) external view returns (Factory memory);
    function motions(uint256) external view returns (Motion memory);
    function lastMotionId() external view returns (uint256);

    // non-view functions
    function acceptTimelockAccess() external;
    function addMotionFactory(address factory, uint256 objectionThreshold, uint256 motionDuration) external;
    function createMotion(address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas) external returns (uint256);
    function queueMotion(uint256 motionId) external returns (bytes32[] memory);
}
