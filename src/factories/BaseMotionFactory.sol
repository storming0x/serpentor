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

    /**
     * @dev internal view function to check if the caller is the gov
     */
    function _onlyGov() internal view {
        require(msg.sender == gov, "!gov");
    }

    /**
     * @dev internal view function to check if the caller is authorized
     */
    function _onlyAuthorized() internal view {
        require(authorized[msg.sender], "!auth");
    }
    
    /**
     * @dev internal function create a motion
     * @param targets array of addresses of the contracts to call
     * @param values array of values to send to each contract
     * @param signatures array of function signatures to call
     * @param calldatas array of calldata to send
     * @return motionId id of the created motion
     */
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

    function cancelMotion(uint256 motionId) external virtual onlyAuthorized {
                _cancelMotion(motionId);
    }

    // create an internal function for canceling a motion
    function _cancelMotion(uint256 motionId) internal virtual {
        LeanTrack(leanTrack).cancelMotion(motionId);
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