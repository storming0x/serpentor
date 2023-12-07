// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import "../BaseMotionFactory.sol";

// This contract is used as an example implementation for testing purposes only
// It is not meant to be used in production and lacks more security checks
/**
 * @dev Example contract for creating motions that transfer tokens
 */
contract BribesToSplitterMotionFactory is BaseMotionFactory {

    //voter = safe.contract('curve-voter.ychad.eth')
    //splitter = safe.contract('bribe-splitter.ychad.eth')
    address public immutable VOTER = 0xF147b8125d2ef93FB6965Db97D6746952a133934;
    address public immutable SPLITTER = 0x527e80008D212E2891C737Ba8a2768a7337D7Fd2;

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

    // function to create a motion that transfers tokens from bribes to splitter
    function createBribesTransferMotion(
        address[] calldata token,
        uint256[] calldata amount
    ) external onlyAuthorized returns (uint256) {
        // iterate over tokens and amounts
        require(token.length == amount.length, "token.length != amount.length");
        address[] memory targets = new address[](token.length);
        uint256[] memory values = new uint256[](token.length);
        string[] memory signatures = new string[](token.length);
        bytes[] memory calldatas = new bytes[](token.length);
        for (uint256 i = 0; i < token.length; i++) {
            require (amount[i] > 0, "!amount");
            require(amount[i] <= transferLimits[token[i]], "amount > limit");
            targets[i] = VOTER;
            values[i] = 0;
            bytes memory calldataForTransfer = abi.encodeWithSignature("transfer(address,uint256)", SPLITTER, amount[i]);
            calldatas[i] = abi.encodeWithSignature("execute(address,uint256,bytes)", token[i], 0, calldataForTransfer);
        }   
        return _createMotion(targets, values, signatures, calldatas);
    }
}