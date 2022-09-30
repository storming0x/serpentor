# @version 0.3.7

"""
@title Yearn SerpentorBravo a governance contract for on-chain voting on proposals
@license GNU AGPLv3
@author yearn.finance
@notice
    A vyper implementation of on-chain voting governance contract for proposals and execution of smart contract calls.
"""
# @dev adjust these settings to your own use case

NAME: constant(String[20]) = "SerpentorBravo"
# buffer for string descriptions. Can use ipfshash
STR_LEN: constant(uint256) = 4000
MAX_DATA_LEN: constant(uint256) = 16608
CALL_DATA_LEN: constant(uint256) = 16483
METHOD_SIG_SIZE: constant(uint256) = 1024

# about 24 hours
MIN_VOTING_PERIOD: constant(uint256) = 5760
# about 2 weeks
MAX_VOTING_PERIOD: constant(uint256) = 80640
MIN_VOTING_DELAY: constant(uint256) = 1
# about 1 week
MAX_VOTING_DELAY: constant(uint256) = 40320

# @notice The minimum setable proposal threshold
MIN_PROPOSAL_THRESHOLD: constant(uint256) = 100 * 10** 18
# @notice The maximum setable proposal threshold
MAX_PROPOSAL_THRESHOLD: constant(uint256) = 5000 * 10 ** 18

# @notice The maximum number of operations in a proposal
MAX_POSSIBLE_OPERATIONS: constant(uint256) = 20

# @notice The EIP-712 typehash for the contract's domain
DOMAIN_TYPE_HASH: constant(bytes32) = keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')
# @notice The EIP-712 typehash for the ballot struct used by the contract
BALLOT_TYPEHASH: constant(bytes32) = keccak256("Ballot(uint256 proposalId,uint8 support)")



# interfaces

# timelock struct
# @notice a single transaction to be executed by the timelock
struct Transaction:
    # @notice the target address for calls to be made
    target: address
    # @notice The value (i.e. msg.value) to be passed to the calls to be made
    amount: uint256
    # @notice The estimated time for execution of the trx
    eta: uint256
    # @notice The function signature to be called
    signature: String[METHOD_SIG_SIZE]
    # @notice The calldata to be passed to the call
    callData: Bytes[CALL_DATA_LEN]

interface Timelock:
    def delay() -> uint256: view
    def GRACE_PERIOD() -> uint256: view
    def acceptQueen(): nonpayable
    def queuedTransactions(hash: bytes32) -> bool: view
    def queueTransaction(trx:Transaction) -> bytes32: nonpayable
    def cancelTransaction(trx:Transaction): nonpayable
    def executeTransaction(trx:Transaction) -> Bytes[MAX_DATA_LEN]: nonpayable

# @dev Comp compatible interface to get Voting weight of account at block number. Some tokens implement 'balanceOfAt' but this call can be adapted to integrate with 'balanceOfAt'
interface GovToken:
    def getPriorVotes(account: address, blockNumber: uint256) -> uint256:view

# @notice Possible states that a proposal may be in
# @dev caution should be taken when modifying this enum since its tightly coupled with internal '_state' method
# @dev vyper enums follow a power of 2 enumeration e.g 1, 2, 4, 8, etc.
enum ProposalState:
    PENDING
    ACTIVE
    CANCELED
    DEFEATED
    SUCCEEDED
    QUEUED
    EXPIRED
    EXECUTED

# @notice a single action to be executed within a proposal
struct ProposalAction:
    # @notice the target address for calls to be made
    target: address
    # @notice The value (i.e. msg.value) to be passed to the calls to be made
    amount: uint256
    # @notice The function signature to be called
    signature: String[METHOD_SIG_SIZE]
    # @notice The calldata to be passed to the call
    callData: Bytes[CALL_DATA_LEN]

# @notice Ballot receipt record for a voter
struct Receipt:
    # @notice Whether or not a vote has been cast
    hasVoted: bool
    # @notice Whether or not the voter supports the proposal or abstains
    support: uint8
    # @notice The number of votes the voter had, which were cast
    votes: uint256

struct Proposal:
    # @notice Unique id for looking up a proposal
    id: uint256
    # @notice Creator of the proposal
    proposer: address
    # @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
    eta: uint256
    # @notice The ordered list of actions this proposal will execute
    actions: DynArray[ProposalAction, MAX_POSSIBLE_OPERATIONS]
    # @notice The block at which voting begins: holders must delegate their votes prior to this block
    startBlock: uint256
    # @notice The block at which voting ends: votes must be cast prior to this block
    endBlock: uint256
    # @notice Current number of votes in favor of this proposal
    forVotes: uint256
    # @notice Current number of votes in opposition to this proposal
    againstVotes: uint256
    # @notice Current number of votes for abstaining for this proposal
    abstainVotes: uint256
    # @notice Flag marking whether the proposal has been canceled
    canceled: bool
    # @notice Flag marking whether the proposal has been executed
    executed: bool

# @notice empress for this contract
queen: public(address)
# @notice pending empress for this contract
pendingQueen: public(address)
# @notice guardian role for this contract
knight: public(address)

# @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
QUORUM_VOTES: immutable(uint256)
# @notice Setting for maximum number of allowed actions a proposal can execute
PROPOSAL_MAX_ACTIONS: immutable(uint256)
# @notice The duration of voting on a proposal, in blocks
votingPeriod: public(uint256)
# @notice The delay before voting on a proposal may take place, once proposed, in blocks
votingDelay: public(uint256)
# @notice The number of votes required in order for a voter to become a proposer
proposalThreshold: public(uint256)
# @notice The address of the Timelock contract
timelock: public(address)
# @notice The address of the governance token
token: public(address)
# @notice The total number of proposals
proposalCount: public(uint256)
# @notice Initial proposal id set at deployment time
# @dev for migrating from other gov systems
initialProposalId: public(uint256)
# @notice The storage record of all proposals ever proposed
proposals: public(HashMap[uint256, Proposal])
# @notice The latest proposal for each proposer
latestProposalIds: public(HashMap[address, uint256])
#  @notice Stores the expiration of account whitelist status as a timestamp
whitelistAccountExpirations: public(HashMap[address, uint256])
#  @notice Receipts of ballots for the entire set of voters, proposal_id -> voter_address -> receipt
receipts: HashMap[uint256, HashMap[address, Receipt]]



# ///// EVENTS /////
# @notice An event emitted when a new proposal is created
event ProposalCreated:
    id: uint256
    proposer: indexed(address)
    actions: DynArray[ProposalAction, MAX_POSSIBLE_OPERATIONS]
    startBlock: uint256
    endBlock: uint256
    description: String[STR_LEN]

# @notice An event emitted when a proposal has been queued in the Timelock
event ProposalQueued:
    id: uint256
    eta: uint256

# @notice An event emitted when a proposal has been executed in the Timelock
event ProposalExecuted:
    id: uint256

# @notice An event emitted when a proposal has been canceled
event ProposalCanceled:
    id: uint256

# @notice An event emitted when a vote has been cast on a proposal
# @param voter The address which casted a vote
# @param proposalId The proposal id which was voted on
# @param support Support value for the vote. 0=against, 1=for, 2=abstain
# @param votes Number of votes which were cast by the voter
# @param reason The reason given for the vote by the voter
event VoteCast:
    voter: indexed(address)
    proposalId: uint256
    support: uint8
    votes: uint256
    reason: String[STR_LEN] 

# @notice Event emitted when the voting delay is set
event VotingDelaySet:
    oldVotingDelay: uint256
    newVotingDelay: uint256

# @notice Event emitted when the voting period is set
event VotingPeriodSet:
    oldVotingPeriod: uint256
    newVotingPeriod: uint256

# @notice Event emitted when the proposal threshold is set
event ProposalThresoldSet:
    oldProposalThreshold: uint256
    newProposalThreshold: uint256

# @notice Event emitted when Whitelisted account expiration is set
event WhitelistAccountExpirationSet:
    account: indexed(address)
    expiration: uint256

# @notice Event emitted when pendingQueen is set
event NewPendingQueen:
    oldPendingQueen: indexed(address)
    newPendingQueen: indexed(address)

# @notice Event emitted when new queen is set
event NewQueen:
    oldQueen: indexed(address)
    newQueen: indexed(address)

# @notice Event emitted when knight is set
event NewKnight:
    oldKnight: indexed(address)
    newKnight: indexed(address)

@external
def __init__(
    timelock: address, 
    queen: address,
    token: address,
    votingPeriod: uint256,
    votingDelay: uint256,
    proposalThreshold: uint256,
    quorumVotes: uint256,
    initialProposalId: uint256
):
    """
    @notice
        Initializes SerpentorBravo contract
    @dev contract supports counter set of initialProposalId to allow migrations
    @param timelock The address of the Timelock contract
    @param token The address of the governance token
    @param votingPeriod The initial voting period
    @param votingDelay The initial voting delay
    @param proposalThreshold The initial proposal threshold
    @param quorumVotes The initial quorum voting setting
    @param initialProposalId The initialProposalId to start the counter
    """
    assert timelock != empty(address), "!timelock"
    assert token != empty(address), "!token"
    assert queen != empty(address), "!queen"
    assert votingPeriod >= MIN_VOTING_PERIOD and votingPeriod <= MAX_VOTING_PERIOD, "!votingPeriod"
    assert votingDelay >= MIN_VOTING_DELAY and votingDelay <= MAX_VOTING_DELAY, "!votingDelay"
    assert proposalThreshold >= MIN_PROPOSAL_THRESHOLD and proposalThreshold <= MAX_PROPOSAL_THRESHOLD, "!proposalThreshold"
    self.timelock = timelock
    self.token = token
    self.queen = queen
    self.votingPeriod = votingPeriod
    self.votingDelay = votingDelay
    self.proposalThreshold = proposalThreshold
    self.initialProposalId = initialProposalId
    self.proposalCount = initialProposalId
    PROPOSAL_MAX_ACTIONS = 10
    QUORUM_VOTES = quorumVotes

@external
def propose(
    actions: DynArray[ProposalAction, MAX_POSSIBLE_OPERATIONS],
    description: String[STR_LEN]
) -> uint256:
    """
    @notice
        Function used to propose a new proposal. Sender must have voting power above the proposal threshold
    @param actions Array of ProposalAction struct with target, value, signature and calldata for executing
    @param description String description of the proposal
    @return Proposal id of new proposal
    """
    # check voting power or whitelist access
    assert GovToken(self.token).getPriorVotes(msg.sender, block.number - 1) > self.proposalThreshold or self._isWhitelisted(msg.sender), "!threshold"

    assert len(actions) != 0, "!no_actions"
    assert len(actions) < PROPOSAL_MAX_ACTIONS, "!too_many_actions"

    latestProposalId: uint256 =  self.latestProposalIds[msg.sender]
    if latestProposalId != 0:
        proposersLatestProposalState: ProposalState = self._state(latestProposalId)
        assert proposersLatestProposalState not in (ProposalState.ACTIVE | ProposalState.PENDING), "!latestPropId_state"

    startBlock: uint256 = block.number + self.votingDelay
    endBlock: uint256 = startBlock + self.votingPeriod

    self.proposalCount += 1

    newProposal: Proposal = Proposal({
        id: self.proposalCount,
        proposer: msg.sender,
        eta: 0,
        actions: actions,
        startBlock: startBlock,
        endBlock: endBlock,
        forVotes: 0,
        againstVotes: 0,
        abstainVotes: 0,
        canceled: False,
        executed: False
    })

    self.proposals[newProposal.id] = newProposal
    self.latestProposalIds[newProposal.proposer] = newProposal.id

    log ProposalCreated(newProposal.id, msg.sender, actions, startBlock, endBlock, description)

    return newProposal.id


@external
def queue(proposalId: uint256):
    """
    @notice Queues a proposal of state succeeded
    @param proposalId The id of the proposal to queue
    """
    assert self._state(proposalId) == ProposalState.SUCCEEDED, "!succeeded"
    eta: uint256 = block.timestamp + Timelock(self.timelock).delay()
    for action in self.proposals[proposalId].actions:
        self._queueOrRevertInternal(action, eta)    
    self.proposals[proposalId].eta = eta
    log ProposalQueued(proposalId, eta)

@external
def execute(proposalId: uint256):
    """
    @notice Executes a queued proposal if eta has passed
    @param proposalId The id of the proposal to execute
    """
    assert self._state(proposalId) == ProposalState.QUEUED, "!queued"
    proposalEta: uint256 = self.proposals[proposalId].eta
    self.proposals[proposalId].executed = True
    for action in self.proposals[proposalId].actions:
        trx: Transaction = self._buildTrx(action, proposalEta)   
        Timelock(self.timelock).executeTransaction(trx)
    
    log ProposalExecuted(proposalId)

@external
def cancel(proposalId: uint256):
    """
    @notice Cancels a proposal only if sender is the proposer, or proposer delegates dropped below proposal threshold
    @param proposalId The id of the proposal to cancel
    """ 
    assert self._state(proposalId) != ProposalState.EXECUTED, "!cancel_executed"
    # proposer can cancel
    proposer: address = self.proposals[proposalId].proposer
    proposalEta: uint256 = self.proposals[proposalId].eta

    if msg.sender != proposer:
        # Whitelisted proposers can't be canceled for falling below proposal threshold unless msg.sender is knight
        if self._isWhitelisted(proposer):
            assert GovToken(self.token).getPriorVotes(proposer, block.number - 1) < self.proposalThreshold and msg.sender == self.knight, "!whitelisted_proposer"
        else:
            assert GovToken(self.token).getPriorVotes(proposer, block.number - 1) < self.proposalThreshold, "!threshold"

    self.proposals[proposalId].canceled = True   
    for action in self.proposals[proposalId].actions:
        trx: Transaction = self._buildTrx(action, proposalEta) 
        Timelock(self.timelock).cancelTransaction(trx)

    log ProposalCanceled(proposalId)

@external
def vote(proposalId: uint256, support: uint8):
    """
    @notice Cast a vote for a proposal
    @param proposalId The id of the proposal
    @param support The support value for the vote. 0=against, 1=for, 2=abstain
    """ 
    log VoteCast(msg.sender, proposalId, support, self._vote(msg.sender, proposalId, support), "")

@external
def voteWithReason(proposalId: uint256, support: uint8, reason: String[STR_LEN]):
    """
    @notice Cast a vote for a proposal with a reason string
    @param proposalId The id of the proposal
    @param support The support value for the vote. 0=against, 1=for, 2=abstain
    """ 
    log VoteCast(msg.sender, proposalId, support, self._vote(msg.sender, proposalId, support), reason)

@external
def voteBySig(proposalId: uint256, support: uint8, v: uint8, r: bytes32, s: bytes32):
    """
    @notice Cast a vote for a proposal by signature
    @dev External function that accepts EIP-712 signatures for voting on proposals.
    """ 
    domainSeparator: bytes32 = self._domainSeparator()
    structHash: bytes32 = keccak256(
        concat(
            BALLOT_TYPEHASH,
            convert(proposalId, bytes32),
            convert(support, bytes32),
        )
    )
    digest: bytes32 = keccak256(
        concat(
            b'\x19\x01',
            domainSeparator,
            structHash,
        )
    )
    signer: address = ecrecover(digest, convert(v, uint256), convert(r, uint256), convert(s, uint256))
    assert signer != empty(address), "!signature"
    log VoteCast(signer, proposalId, support, self._vote(signer, proposalId, support), "")

@external
def setVotingDelay(newVotingDelay: uint256):
    """
    @notice Admin function for setting the voting delay
    @param newVotingDelay new voting delay, in blocks
    """
    assert msg.sender == self.queen, "!queen"
    assert newVotingDelay >= MIN_VOTING_DELAY and newVotingDelay <= MAX_VOTING_DELAY, "!votingDelay"
    oldVotingDelay: uint256 = self.votingDelay
    self.votingDelay = newVotingDelay

    log VotingDelaySet(oldVotingDelay, newVotingDelay)

@external
def setVotingPeriod(newVotingPeriod: uint256):
    """
    @notice Admin function for setting the voting period
    @param newVotingPeriod new voting period, in blocks
    """
    assert msg.sender == self.queen, "!queen"
    assert newVotingPeriod >= MIN_VOTING_PERIOD and newVotingPeriod <= MAX_VOTING_PERIOD, "!votingPeriod"
    oldVotingPeriod: uint256 = self.votingPeriod
    self.votingPeriod = newVotingPeriod

    log VotingPeriodSet(oldVotingPeriod, newVotingPeriod)

@external
def setProposalThreshold(newProposalThreshold: uint256):
    """
    @notice Admin function for setting the proposal threshold
    @param newProposalThreshold must be in required range
    """
    assert msg.sender == self.queen, "!queen"
    assert newProposalThreshold >= MIN_PROPOSAL_THRESHOLD and newProposalThreshold <= MAX_PROPOSAL_THRESHOLD, "!threshold"
    oldProposalThreshold: uint256 = self.proposalThreshold
    self.proposalThreshold = newProposalThreshold

    log ProposalThresoldSet(oldProposalThreshold, newProposalThreshold)

@external
def setWhitelistAccountExpiration(account: address, expiration: uint256):
    """
    @notice Admin function for setting the whitelist expiration as a timestamp for an account. Whitelist status allows accounts to propose without meeting threshold
    @param account Account address to set whitelist expiration for
    @param expiration Expiration for account whitelist status as timestamp (if now < expiration, whitelisted)
    """

    assert msg.sender == self.queen or msg.sender == self.knight, "!access"
    self.whitelistAccountExpirations[account] = expiration

    log WhitelistAccountExpirationSet(account, expiration)

@external
def setPendingQueen(newPendingQueen: address):
    """
    @notice Begins transfer of crown and governor rights. The new queen must call `acceptThrone`
    @dev Admin function to begin exchange of queen. The newPendingQueen must call `acceptThrone` to finalize the transfer.
    @param newPendingQueen New pending queen.
    """
    assert msg.sender == self.queen, "!queen"
    oldPendingQueen: address = self.pendingQueen
    self.pendingQueen = newPendingQueen

    log NewPendingQueen(oldPendingQueen, newPendingQueen)

@external
def acceptThrone():
    """
    @notice Accepts transfer of crown and governor rights
    @dev msg.sender must be pendingQueen
    """
    assert msg.sender == self.pendingQueen, "!pendingQueen"
    # save values for events
    oldQueen: address = self.queen
    oldPendingQueen: address = self.pendingQueen
    # new ruler
    self.queen = self.pendingQueen
    # clean up
    self.pendingQueen = empty(address)

    log NewQueen(oldQueen, self.queen)
    log NewPendingQueen(oldPendingQueen, empty(address))



@external
def setKnight(newKnight: address):
    """
    @notice Admin function for setting the knight for this contract
    @param newKnight Account configured to be the knight, set to 0x0 to remove knight
    """
    assert msg.sender == self.queen, "!queen"
    oldKnight: address = self.knight
    self.knight = newKnight

    log NewKnight(oldKnight, newKnight)

@external
@view
def state(proposalId: uint256)  -> ProposalState:
    """
    @notice returns enum value of proposalId 
    @dev when calling this method from ABI interfaces be aware enums in vyper have a different enumeration from solidity enums.
    @dev also check `ordinalState()` method
    @param proposalId Id of proposal
    """
    return self._state(proposalId)


@external
@view
def ordinalState(proposalId: uint256) -> uint8:
    """
    @notice returns ordinal value of proposalId which is different from enum value
    @dev function to support compatibility with solidity enums
    @dev also check `state()` method
    @param proposalId Id of proposal
    """
    proposalState: ProposalState = self._state(proposalId)
    if proposalState == ProposalState.PENDING:
        return 0
    elif proposalState == ProposalState.ACTIVE:
        return 1
    elif proposalState == ProposalState.CANCELED:
        return 2
    elif proposalState == ProposalState.DEFEATED:
        return 3
    elif proposalState == ProposalState.SUCCEEDED:
        return 4
    elif proposalState == ProposalState.QUEUED:
        return 5
    elif proposalState == ProposalState.EXPIRED:
        return 6
    else:
        return 7

@external
@view
def isWhitelisted(account: address) -> bool:
    return self._isWhitelisted(account)

@external
@view
def getActions(proposalId: uint256) -> DynArray[ProposalAction, MAX_POSSIBLE_OPERATIONS]:
    """
    @notice Gets actions of a proposal
    @param proposalId the id of the proposal
    @return Targets, values, signatures, and calldatas of the proposal actions
    """
    return self.proposals[proposalId].actions

@external
@view
def getReceipt(proposalId: uint256, voter: address) -> Receipt:
    """
    @notice Gets the receipt for a voter on a given proposal
    @param proposalId the id of the proposal
    @param voter The address of the voter
    @return The voting receipt
    """
    return self._getReceipt(proposalId, voter)

@external
@view
def proposalMaxActions() -> uint256:
    return PROPOSAL_MAX_ACTIONS

@external
@view
def quorumVotes() -> uint256:
    return QUORUM_VOTES

@external
@view 
def domainSeparator() -> bytes32:
    """
    @notice Gets the domain separator
    @return Domain separator of contract
    """
    return self._domainSeparator()

@external
@view
def name() -> String[20]:
    return NAME

@internal
def _queueOrRevertInternal(action: ProposalAction, eta: uint256):
    trxHash: bytes32 = keccak256(_abi_encode(action.target, action.amount, action.signature, action.callData, eta))
    assert Timelock(self.timelock).queuedTransactions(trxHash) != True, "!duplicate_trx"
    timelockTrx: Transaction = self._buildTrx(action, eta)
    Timelock(self.timelock).queueTransaction(timelockTrx)

@internal
def _buildTrx(action: ProposalAction, eta: uint256) -> Transaction:
    timelockTrx: Transaction = Transaction({
        target: action.target,
        amount: action.amount,
        eta: eta,
        signature: action.signature,
        callData: action.callData,
    })

    return timelockTrx

@internal
@view
def _domainSeparator() -> bytes32:
    return keccak256(
        concat(
            DOMAIN_TYPE_HASH,
            keccak256(convert(NAME, Bytes[20])),
            keccak256("1"),
            convert(chain.id, bytes32),
            convert(self, bytes32)
        )
    )

@internal
def _vote(voter: address, proposalId: uint256, support: uint8) -> uint256:
    """
    @notice Internal function for voting logic
    @param voter The voter that is casting their vote
    @param proposalId The id of the proposal to vote on
    @param support The support value for the vote. 0=against, 1=for, 2=abstain
    @return The number of votes cast
    """
    assert self._state(proposalId) == ProposalState.ACTIVE, "!active"
    assert support <= 2, "!vote_type" 
    assert self._getHasVoted(proposalId, voter) == False, "!hasVoted"
    # @dev use min of current block and proposal startBlock instead ?
    votes:uint256 = GovToken(self.token).getPriorVotes(voter, self.proposals[proposalId].startBlock)
    
    if support == 0:
        self.proposals[proposalId].againstVotes += votes
    elif support == 1:
        self.proposals[proposalId].forVotes += votes
    elif support == 2:
        self.proposals[proposalId].abstainVotes += votes

    self.receipts[proposalId][voter].hasVoted = True
    self.receipts[proposalId][voter].support = support
    self.receipts[proposalId][voter].votes = votes

    return votes

@internal
@view
def _state(proposalId: uint256) -> ProposalState:
    assert self.proposalCount >= proposalId and proposalId > self.initialProposalId, "!proposalId"

    if self.proposals[proposalId].canceled:
        return ProposalState.CANCELED
    elif block.number <= self.proposals[proposalId].startBlock:
        return ProposalState.PENDING
    elif block.number <= self.proposals[proposalId].endBlock:
        return ProposalState.ACTIVE
    elif self.proposals[proposalId].forVotes <= self.proposals[proposalId].againstVotes or self.proposals[proposalId].forVotes < QUORUM_VOTES:
        return ProposalState.DEFEATED
    elif self.proposals[proposalId].eta == 0:
         return ProposalState.SUCCEEDED
    elif self.proposals[proposalId].executed:
        return ProposalState.EXECUTED
    elif block.timestamp >= self.proposals[proposalId].eta + Timelock(self.timelock).GRACE_PERIOD():
        return ProposalState.EXPIRED
    else:
        return ProposalState.QUEUED

@internal
@view
def _isWhitelisted(account: address) -> bool:
    return self.whitelistAccountExpirations[account] > block.timestamp

@internal
@view
def _getReceipt(proposalId: uint256, voter: address) -> Receipt:
    return self.receipts[proposalId][voter]

@internal
@view
def _getHasVoted(proposalId: uint256, voter: address) -> bool:
    return self.receipts[proposalId][voter].hasVoted