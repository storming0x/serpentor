// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

// mock vault for testing purposes
contract MockVault {

    address public immutable gov;

    mapping(address => uint256) public performanceFee;
    // deposit limit set to MAX_UINT256 by default
    uint256 public depositLimit = type(uint256).max;

    // modifier for onlyGov
    modifier onlyGov() {
        _onlyGov();
        _;
    }

    constructor(address _gov) {
        gov = _gov;
    }

    // check if the caller is the gov
    function _onlyGov() internal view {
        require(msg.sender == gov, "!gov");
    }

    // method that management cannot call
    function updateStrategyPerformanceFee(address _strategy, uint256 _performanceFee) external onlyGov {
        performanceFee[_strategy] = _performanceFee;
    }
    // method that management cannot call
    function setDepositLimit(uint256 _depositLimit) external onlyGov {
        depositLimit = _depositLimit;
    }
}