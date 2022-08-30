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
    uint256 abstainVotes;
    bool canceled;
    bool executed;
}

interface SerpentorBravo {
    // view functions
    function queen() external view returns (address);
    function pendingQueen() external view returns (address);
    function knight() external view returns (address);
    function timelock() external view returns (address);
    function token() external view returns (address);
    function votingPeriod() external view returns (uint256);
    function votingDelay() external view returns (uint256);
    function quorumVotes() external view returns (uint256);
    function proposalThreshold() external view returns (uint256);
    function initialProposalId() external view returns (uint256);
    function proposalMaxActions() external view returns (uint256);
    function proposalCount() external view returns (uint256);
    function proposals(uint256 proposalId) external view returns (Proposal memory);
    function latestProposalIds(address account) external view returns (uint256);
    function state(uint256 proposalId) external view returns (ProposalState);
    function ordinalState(uint256 proposalId) external view returns (uint8);
    function isWhitelisted(address account) external view returns (bool);

    // state changing funcs
    function setPendingQueen(address newQueen) external;
    function acceptThrone() external;
    function propose(ProposalAction[] calldata actions, string calldata description) external returns (uint256);
    function cancel(uint256 proposalId) external;
    function setWhitelistAccountExpiration(address account, uint256 expiration) external;
    function setKnight(address newKnight) external;
    
}