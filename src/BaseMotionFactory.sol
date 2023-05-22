// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

interface LeanTrack {
     /**
     * @dev view functions
     */
    function createMotion(address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas) external returns (uint256);
    function queueMotion(uint256 motionId) external returns (bytes32[] memory);
    function enactMotion(uint256 motionId) external;
    function cancelMotion(uint256 motionId) external;
    function objectToMotion(uint256 motionId) external; 
}

abstract contract BaseMotionFactory {

    address public immutable leanTrack;
    address public immutable gov;
    // authorized roles for this factory to execute restricted calls
    mapping(address => bool) public authorized;

    modifier onlyAuthorized() {
        _onlyAuthorized();
        _;
    }

    modifier onlyGov() {
        _onlyGov();
        _;
    }

    constructor(address _leanTrack, address _gov) {
        leanTrack = _leanTrack;
        gov = _gov;
    }

    function _onlyGov() internal view {
        require(msg.sender == gov, "!gov");
    }

    function _onlyAuthorized() internal view {
        require(authorized[msg.sender], "!auth");
    }

    function _createMotion(
        address[] memory targets, 
        uint256[] memory values, 
        string[] memory signatures, 
        bytes[] memory calldatas
    ) internal virtual returns (uint256) {
        return LeanTrack(leanTrack).createMotion(
            targets, 
            values, 
            signatures, 
            calldatas
        );
    }

    /**
     * @dev set authorized roles for this factory to execute restricted calls
     * @param _authorized address of the authorized role
     * @param _status status of the authorized role
     * @notice only gov can call this function
     * @notice doesnt handle separate granular roles, implementations should handle usage of these authorized addresses
     */
    function setAuthorized(address _authorized, bool _status) external onlyGov {
        authorized[_authorized] = _status;
    }
}