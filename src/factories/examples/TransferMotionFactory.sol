// SPDX-License-Identifier: AGPL

pragma solidity ^0.8.17;

import "../BaseMotionFactory.sol";

// This contract is used as an example implementation for testing purposes only
// It is not meant to be used in production and lacks more security checks
/**
 * @dev Example contract for creating motions that transfer tokens
 */
contract TransferMotionFactory is BaseMotionFactory {

    // mapping that handle transfer limits for each token
    mapping(address => uint256) public transferLimits;
    
    constructor(address _leanTrack, address _gov) BaseMotionFactory(_leanTrack, _gov) {}

    // function to set transfer limits for a token
    function setTransferLimit(address token, uint256 limit) external onlyGov {
        require(limit > 0, "> 0");
        transferLimits[token] = limit;
    }

    function disallowTokenTransfer(address token) external onlyGov {
        transferLimits[token] = 0;
    }

    // function to create a motion that transfers tokens
    function createTransferMotion(
        address token,
        address to,
        uint256 amount
    ) external onlyAuthorized returns (uint256) {
        require (amount > 0, "!amount");
        require(amount <= transferLimits[token], "amount > limit");
        address[] memory targets = new address[](1);
        targets[0] = token;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        string[] memory signatures = new string[](1);
        signatures[0] = "transfer(address,uint256)";
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encode(to, amount);
        return _createMotion(targets, values, signatures, calldatas);
    }
}