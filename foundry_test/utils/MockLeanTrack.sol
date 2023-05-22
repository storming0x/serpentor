// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;


struct MotionArgs {
        address[] targets;
        uint256[] values; 
        string[] signatures; 
        bytes[] calldatas;
    }

contract MockLeanTrack {
    event MotionCreated(
        address[] targets, 
        uint256[] values, 
        string[] signatures, 
        bytes[] calldatas
    );

    // mapping with motion args
    mapping(uint256 => MotionArgs) private _motions;

    function createMotion(
        address[] memory targets, 
        uint256[] memory values, 
        string[] memory signatures, 
        bytes[] memory calldatas
    ) external returns (uint256) {
        uint256 motionId = 1;
        _motions[motionId] = MotionArgs(targets, values, signatures, calldatas);

        return 1;
    }

    function getMotionArgs(uint256 motionId) external view returns (MotionArgs memory) {
        return _motions[motionId];
    }
}