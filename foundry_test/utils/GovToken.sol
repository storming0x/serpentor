// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import "@openzeppelin/utils/math/SafeMath.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

// mock gov token
contract GovToken is ERC20 {
    mapping(address => bool) public _blocked;
    mapping(address => mapping(uint256 => uint256)) votingPower;
    bool public useBalanceOfForVotingPower;


    constructor(uint8 _decimals) ERC20("yearn.finance test token", "TEST") {
        _mint(msg.sender, 30000 * 10**uint256(_decimals));
    }

    function _setBlocked(address user, bool value) public virtual {
        _blocked[user] = value;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20) {
        require(!_blocked[to], "Token transfer refused. Receiver is on blacklist");
        super._beforeTokenTransfer(from, to, amount);
    }

    function _setVotingPower(address account, uint256 blockNumber, uint256 balance) external {
        votingPower[account][blockNumber] = balance;
    }

    function _setUseBalanceOfForVotingPower(bool flag) external {
        useBalanceOfForVotingPower = flag;
    }

    function getPriorVotes(address account, uint blockNumber) external view returns (uint256) {
        if (useBalanceOfForVotingPower) {
            return balanceOf(account);
        }

        return votingPower[account][blockNumber];
    }


}