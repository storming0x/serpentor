// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

struct MotionArgs {
        uint256 id;
        address[] targets;
        uint256[] values; 
        string[] signatures; 
        bytes[] calldatas;
    }

contract MockLeanTrack {
    event MotionCreated(
        uint256 indexed motionId,
        address indexed proposer,
        address[] targets, 
        uint256[] values, 
        string[] signatures, 
        bytes[] calldatas,
        uint256 timeForQueue,
        uint256 snapshotBlock,
        uint256 objectionsThreshold
    );  

    uint256 public motionCount = 0;

    // mapping with motion args
    mapping(uint256 => MotionArgs) private _motions;

    function createMotion(
        address[] memory targets, 
        uint256[] memory values, 
        string[] memory signatures, 
        bytes[] memory calldatas
    ) external returns (uint256) {
        motionCount++;
        uint256 motionId = motionCount;
        _motions[motionId] = MotionArgs(motionId, targets, values, signatures, calldatas);

        emit MotionCreated(
            motionId,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            0,
            0,
            0
        );

        return motionId;
    }

    function getMotionArgs(uint256 motionId) external view returns (MotionArgs memory) {
        return _motions[motionId];
    }

    function cancelMotion(uint256 motionId) external {
        delete _motions[motionId];
    }

    function motions(uint256 motionId) external view returns (MotionArgs memory) {
        return _motions[motionId];
    }
}