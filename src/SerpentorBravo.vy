# @version 0.3.6

# @dev adjust these settings to your own use case

NAME: constant(String[20]) = "Serpentor Bravo"
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
    # @notice The function signature to be called
    signature: String[METHOD_SIG_SIZE]
    # @notice The calldata to be passed to the call
    callData: Bytes[CALL_DATA_LEN]
    # @notice The estimated time for execution of the trx
    eta: uint256

interface Timelock:
    def delay() -> uint256: view
    def GRACE_PERIOD() -> uint256: view
    def acceptQueen(): nonpayable
    def queuedTransactions(hash: bytes32) -> bool: view
    def queueTransaction(trx:Transaction) -> bytes32: nonpayable
    def cancelTransaction(trx:Transaction): nonpayable
    def executeTransaction(trx:Transaction) -> Bytes[MAX_DATA_LEN]: nonpayable

# @notice Possible states that a proposal may be in
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

# @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
quorumVotes: public(uint256)
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
# @notice Setting for maximum number of allowed actions a proposal can execute
proposalMaxActions: public(uint256)
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
    description: String[MAX_DATA_LEN]

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
    reason: String[MAX_DATA_LEN] 


@external
def __init__(
    timelock: address, 
    token: address,
    votingPeriod: uint256,
    votingDelay: uint256,
    proposalThreshold: uint256,
    quorumVotes: uint256,
    initialProposalId: uint256
):
    """
    @notice
    @dev
    @param 
    """
    assert timelock != empty(address), "!timelock"
    assert token != empty(address), "!token"
    assert votingPeriod >= MIN_VOTING_PERIOD and votingPeriod <= MAX_VOTING_PERIOD, "!votingPeriod"
    assert votingDelay >= MIN_VOTING_DELAY and votingDelay <= MAX_VOTING_DELAY, "!votingDelay"
    assert proposalThreshold >= MIN_PROPOSAL_THRESHOLD and proposalThreshold <= MAX_PROPOSAL_THRESHOLD, "!proposalThreshold"
    self.timelock = timelock
    self.token = token
    self.votingPeriod = votingPeriod
    self.votingDelay = votingDelay
    self.proposalThreshold = proposalThreshold
    self.quorumVotes = quorumVotes
    self.initialProposalId = initialProposalId

@external
def propose(
    actions: DynArray[ProposalAction, MAX_POSSIBLE_OPERATIONS],
    description: String[MAX_DATA_LEN]
) -> uint256:
    """
    @notice
    @dev
    @param 
    """
    # TODO: check msg.sender has voting power in token to add a proposal
    # // Allow addresses above proposal threshold and whitelisted addresses to propose
    # require(comp.getPriorVotes(msg.sender, sub256(block.number, 1)) > proposalThreshold || isWhitelisted(msg.sender), "proposer votes below proposal threshold");

    assert len(actions) != 0, "!no_actions"
    assert len(actions) <= self.proposalMaxActions, "!too_many_actions"

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
    @dev
    @param proposalId The id of the proposal to queue
    """
    assert self._state(proposalId) == ProposalState.SUCCEEDED, "!succeeded"
    proposal: Proposal = self.proposals[proposalId]
    eta: uint256 = block.timestamp + Timelock(self.timelock).delay()
    for action in proposal.actions:
        self._queueOrRevertInternal(action, eta)    
    proposal.eta = eta
    log ProposalQueued(proposalId, eta)

@external
def execute(proposalId: uint256):
    """
    @notice Executes a queued proposal if eta has passed
    @dev
    @param proposalId The id of the proposal to execute
    """
    assert self._state(proposalId) == ProposalState.QUEUED, "!queued"
    proposal: Proposal = self.proposals[proposalId]
    proposal.executed = True
    for action in proposal.actions:
        trx: Transaction = self._buildTrx(action, proposal.eta)   
        Timelock(self.timelock).executeTransaction(trx)
    
    log ProposalExecuted(proposalId)

@external
def cancel(proposalId: uint256):
    """
    @notice Cancels a proposal only if sender is the proposer, or proposer delegates dropped below proposal threshold
    @param proposalId The id of the proposal to cancel
    """ 
    assert self._state(proposalId) != ProposalState.EXECUTED, "!cancel_executed"
    proposal: Proposal = self.proposals[proposalId]
    # proposer can cancel
    proposer: address = proposal.proposer
    # TODO: implement weight vote checks. Ref: https://github.com/compound-finance/compound-protocol/blob/a3214f67b73310d547e00fc578e8355911c9d376/contracts/Governance/GovernorBravoDelegate.sol#L164
    # if msg.sender != proposer:
        # Whitelisted proposers can't be canceled for falling below proposal threshold
        # if self._isWhitelisted(proposer):

        # else

    proposal.canceled = True
    for action in proposal.actions:
        trx: Transaction = self._buildTrx(action, proposal.eta)   
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
def voteWithReason(proposalId: uint256, support: uint8, reason: String[MAX_DATA_LEN]):
    """
    @notice Cast a vote for a proposal with a reason string
    @param proposalId The id of the proposal
    @param support The support value for the vote. 0=against, 1=for, 2=abstain
    """ 
    log VoteCast(msg.sender, proposalId, support, self._vote(msg.sender, proposalId, support), reason)

@external
@view
def state(proposalId: uint256)  -> ProposalState:
    return self._state(proposalId)

@external
@view
def isWhitelisted(account: address) -> bool:
    return self._isWhitelisted(account)

@external
@view
def getActions(proposalId: uint256) -> DynArray[ProposalAction, MAX_POSSIBLE_OPERATIONS]:
    """
    @notice Gets actions of a proposal
    @dev
    @param proposalId the id of the proposal
    @return Targets, values, signatures, and calldatas of the proposal actions
    """
    proposal: Proposal = self.proposals[proposalId]
    return proposal.actions

@external
@view
def getReceipt(proposalId: uint256, voter: address) -> Receipt:
    """
    @notice Gets the receipt for a voter on a given proposal
    @dev
    @param proposalId the id of the proposal
    @param voter The address of the voter
    @return The voting receipt
    """
    return self._getReceipt(proposalId, voter)

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
        signature: action.signature,
        callData: action.callData,
        eta: eta
    })

    return timelockTrx

@internal
def _vote(voter: address, proposalId: uint256, support: uint8) -> uint256:
    """
    @notice Internal function for voting logic
    @dev
    @param voter The voter that is casting their vote
    @param proposalId The id of the proposal to vote on
    @param support The support value for the vote. 0=against, 1=for, 2=abstain
    @return The number of votes cast
    """
    assert self._state(proposalId) == ProposalState.ACTIVE, "!active"
    assert support <= 2, "!vote_type" # @dev can we use enums instead?
    proposal: Proposal = self.proposals[proposalId]
    receipt: Receipt = self._getReceipt(proposalId, voter)
    assert receipt.hasVoted == False, "hasVoted"
    # TODO: port get votes at prior start block
    # Ref: https://github.com/compound-finance/compound-protocol/blob/a3214f67b73310d547e00fc578e8355911c9d376/contracts/Governance/GovernorBravoDelegate.sol#L276
    # TODO: implement
    return 0


@internal
@view
def _state(proposalId: uint256) -> ProposalState:
    assert self.proposalCount >= proposalId and proposalId > self.initialProposalId, "!proposalId"

    proposal: Proposal = self.proposals[proposalId]

    if proposal.canceled:
        return ProposalState.CANCELED
    elif block.number <= proposal.startBlock:
        return ProposalState.PENDING
    elif block.number <= proposal.endBlock:
        return ProposalState.ACTIVE
    elif proposal.forVotes <= proposal.againstVotes or proposal.forVotes < self.quorumVotes:
        return ProposalState.DEFEATED
    elif proposal.eta == 0:
         return ProposalState.SUCCEEDED
    elif proposal.executed:
        return ProposalState.EXECUTED
    elif block.timestamp >= proposal.eta + Timelock(self.timelock).GRACE_PERIOD():
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