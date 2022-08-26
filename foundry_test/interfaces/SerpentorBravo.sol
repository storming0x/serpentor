// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

struct ProposalAction {
    address target;
    uint256 amount;
    string signature;  
    bytes callData;
}

struct Proposal {
    uint256 id;
    address proposer;
    uint256 eta;
    ProposalAction[] actions;
    uint256 startBlock;
    uint256 endBlock;
    uint256 forVotes;
    uint256 againstVotes;
    bool canceled;
    bool executed;
}

interface SerpentorBravo {
    // view functions
    function queen() external view returns (address);
    function pendingQueen() external view returns (address);
    function timelock() external view returns (address);
    function token() external view returns (address);
    function votingPeriod() external view returns (uint256);
    function votingDelay() external view returns (uint256);
    function quorumVotes() external view returns (uint256);
    function proposalThreshold() external view returns (uint256);
    function initialProposalId() external view returns (uint256);
    function proposalMaxActions() external view returns (uint256);
    // state changing funcs
    function setPendingQueen(address newQueen) external;
    function acceptThrone() external;
    function propose(ProposalAction[] calldata actions, string calldata description) external returns (uint256);
}