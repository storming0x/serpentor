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
interface Timelock:
    def delay() -> uint256: view
    def GRACE_PERIOD() -> uint256: view
    def acceptQueen(): nonpayable
    def queuedTransactions(hash: bytes32) -> bool: view
    def queuedTransaction(target: address, amount: uint256, signature: String[METHOD_SIG_SIZE], data: Bytes[CALL_DATA_LEN], eta: uint256) -> bytes32: nonpayable
    def cancelTransaction(target: address, amount: uint256, signature: String[METHOD_SIG_SIZE], data: Bytes[CALL_DATA_LEN], eta: uint256): nonpayable
    def executeTransaction(target: address, amount: uint256, signature: String[METHOD_SIG_SIZE], data: Bytes[CALL_DATA_LEN], eta: uint256) -> Bytes[MAX_DATA_LEN]: nonpayable

# @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
quorumVotes: public(uint256)
# @notice The duration of voting on a proposal, in blocks
votingPeriod: public(uint256)
# @notice The delay before voting on a proposal may take place, once proposed, in blocks
votingDelay: public(uint256)
proposalThreshold: public(uint256)
timelock: public(address)
token: public(address)
proposalMaxActions: public(uint256)
# @notice The total number of proposals
proposalCount: public(uint256)

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

#  @notice Receipts of ballots for the entire set of voters, proposal_id -> voter_address -> receipt
receipts: HashMap[uint256, HashMap[address, Receipt]]

@external
def __init__(
    timelock: address, 
    token: address,
    votingPeriod: uint256,
    votingDelay: uint256,
    proposalThreshold: uint256,
    quorumVotes: uint256
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


    return 0