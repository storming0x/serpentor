// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

// vyper enums have different enumeration number from solidity
enum ProposalState {
    PENDING,
    ACTIVE,
    CANCELED,
    DEFEATED,  
    SUCCEEDED,
    QUEUED,
    EXPIRED,
    EXECUTED
}

struct Proposal {
    uint256 id;
    address proposer;
    uint256 eta;
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;
    uint256 startBlock;
    uint256 endBlock;
    uint256 forVotes;
    uint256 againstVotes;
    uint256 abstainVotes;
    bool canceled;
    bool executed;
}

struct Receipt {
    bool hasVoted;
    uint8 support;
    uint256 votes;
}

interface SerpentorBravo {
    // view functions
    function admin() external view returns (address);
    function pendingAdmin() external view returns (address);
    function knight() external view returns (address);
    function timelock() external view returns (address);
    function token() external view returns (address);
    function votingPeriod() external view returns (uint256);
    function votingDelay() external view returns (uint256);
    function quorumVotes() external view returns (uint256);
    function proposalThreshold() external view returns (uint256);
    function initialProposalId() external view returns (uint256);
    function proposalMaxOperations() external view returns (uint256);
    function proposalCount() external view returns (uint256);
    function proposals(uint256 proposalId) external view returns (Proposal memory);
    function latestProposalIds(address account) external view returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
    function enumState(uint256 proposalId) external view returns (ProposalState);
    function isWhitelisted(address account) external view returns (bool);
    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory);
    function getActions(uint256 proposalId) external view returns (address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas);
    function domainSeparator() external view returns (bytes32);
    function name() external view returns (string memory);

    // state changing funcs
    function setPendingAdmin(address newAdmin) external;
    function acceptAdmin() external;
    function propose(address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) external returns (uint256);
    function cancel(uint256 proposalId) external;
    function setWhitelistAccountExpiration(address account, uint256 expiration) external;
    function setKnight(address newKnight) external;
    function castVote(uint256 proposalId, uint8 support) external;
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external;
    function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external;
    function setVotingDelay(uint256 votingDelay) external;
    function setVotingPeriod(uint256 votingPeriod) external;
    function setProposalThreshold(uint256 proposalThreshold) external;
    function queue(uint256 proposalId) external;
    function execute(uint256 proposalId) external payable;
}