# @version 0.3.7

"""
@title Yearn LeanTrack an optimistic governance contract
@license GNU AGPLv3
@author yearn.finance
@notice
    A vyper implementation of on-chain optimistic governance contract for motion proposals and management of smart contract calls.
"""

NAME: constant(String[20]) = "LeanTrack"
# buffer for string descriptions. Can use ipfshash
STR_LEN: constant(uint256) = 4000
# these values are reasonable estimates from historical onchain data of compound and other gov systems
MAX_DATA_LEN: constant(uint256) = 16608
CALL_DATA_LEN: constant(uint256) = 16483
METHOD_SIG_SIZE: constant(uint256) = 1024
# @notice The maximum number of operations in a motion
MAX_POSSIBLE_OPERATIONS: constant(uint256) = 10
# @notice lower bound for objection threshold settings
# @dev represented in basis points (1% = 100)
MIN_OBJECTIONS_THRESHOLD: constant(uint256) = 100
# @notice upper bound for objections threshold settings
# @dev represented in basis points (30% = 3000)
MAX_OBJECTIONS_THRESHOLD: constant(uint256) = 3000
# @dev minimum time in seconds for queueing motion allows for 1 hour of objections
# @dev left low for emergency situations, factories can set higher values for non emergency operations
MIN_MOTION_DURATION: constant(uint256) = 1 # 1 second
HUNDRED_PERCENT: constant(uint256) = 10000 # 100%

### interfaces

# @dev compatible interface for DualTimelock implementations
# @dev DualTimelock is a contract that can queue and execute transactions. Should be possible to change interface to common timelock interfaces
interface DualTimelock:
    def leanTrackDelay() -> uint256: view
    def acceptLeanTrack() : nonpayable
    def queuedRapidTransactions(hash: bytes32) -> bool: view
    def queueRapidTransaction(target: address, amount: uint256, signature: String[METHOD_SIG_SIZE], data: Bytes[CALL_DATA_LEN], eta: uint256) -> bytes32: nonpayable
    def cancelRapidTransaction(target: address, amount: uint256, signature: String[METHOD_SIG_SIZE], data: Bytes[CALL_DATA_LEN], eta: uint256): nonpayable
    def executeRapidTransaction(target: address, amount: uint256, signature: String[METHOD_SIG_SIZE], data: Bytes[CALL_DATA_LEN], eta: uint256) -> Bytes[MAX_DATA_LEN]: payable

# @dev Comp compatible interface to get Voting weight of account at block number. Some tokens implement 'balanceOfAt' but this call can be adapted to integrate with 'balanceOfAt'
interface GovToken:
    def getPriorVotes(account: address, blockNumber: uint256) -> uint256:view
    def totalSupplyAt(blockNumber: uint256) -> uint256: view

### structs

# @notice A struct to represent a Factory Settings
struct Factory:
    # @notice The objections threshold for the factory proposed motions
    objectionsThreshold: uint256
    # @notice the minimum time in seconds that must pass before the factory motions can be queued
    motionDuration: uint256
    # @notice is factory flag
    isFactory: bool

# @notice A struct to represent a motion
struct Motion:
    # @notice The id of the motion
    id: uint256
    # @notice The address of the proposer
    proposer: address
    # @notice The ordered list of target addresses for calls to be made in motion
    targets: DynArray[address, MAX_POSSIBLE_OPERATIONS]
    # @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made in motion
    values: DynArray[uint256, MAX_POSSIBLE_OPERATIONS]
    # @notice The ordered list of function signatures to be called in motion
    signatures: DynArray[String[METHOD_SIG_SIZE], MAX_POSSIBLE_OPERATIONS]
    # @notice The ordered list of calldatas to be passed to each call to be made in motion
    calldatas: DynArray[Bytes[CALL_DATA_LEN], MAX_POSSIBLE_OPERATIONS]
    # @notice The block.timestamp when the motion can be queued to the timelock 
    timeForQueue: uint256
    # @notice The block number at which the motion was created
    snapshotBlock: uint256
    # @notice The number of objections against the motion
    objections: uint256
    # @notice The objection threshold to defeat the motion
    objectionsThreshold: uint256
    # @notice The timestamp for when the motion can be executed in timelock
    eta: uint256
    # @notice The flag to indicate if the motion has been queued to the timelock
    isQueued: bool


# ///// EVENTS /////
event MotionFactoryAdded:
    factory: indexed(address)
    objectionThreshold: uint256
    motionDuration: uint256  

event MotionFactoryRemoved:
    factory: indexed(address)  

event ExecutorAdded:
    executor: indexed(address)

event ExecutorRemoved:
    executor: indexed(address)

event Paused:
    account: indexed(address)

event Unpaused:
    account: indexed(address)

event KnightSet:
    knight: indexed(address)

event MotionCreated:
    motionId: indexed(uint256)
    proposer: indexed(address)
    targets: DynArray[address, MAX_POSSIBLE_OPERATIONS]
    values: DynArray[uint256, MAX_POSSIBLE_OPERATIONS]
    signatures: DynArray[String[METHOD_SIG_SIZE], MAX_POSSIBLE_OPERATIONS]
    calldatas: DynArray[Bytes[CALL_DATA_LEN], MAX_POSSIBLE_OPERATIONS]
    timeForQueue: uint256
    snapshotBlock: uint256
    objectionThreshold: uint256

event MotionQueued:
    motionId: indexed(uint256)
    trxHashes: DynArray[bytes32, MAX_POSSIBLE_OPERATIONS]
    eta: uint256

event MotionEnacted:
    motionId: indexed(uint256)

event MotionObjected:
    motionId: indexed(uint256)
    objector: indexed(address)
    objectorBalance: uint256
    newObjectionsAmount: uint256
    newObjectionsAmountPct: uint256

event MotionRejected:
    motionId: indexed(uint256)

event MotionCanceled:
    motionId: indexed(uint256)

### state fields
# @notice The address of the admin
admin: public(address)
# @notice The address of the pending admin
pendingAdmin: public(address)
# @notice The address of the guardian role
knight: public(address)
# @notice Boolean flag to indicate if the contract is paused
paused: public(bool)
# @notice The address of the governance token
token: public(address)
# @notice The address of the timelock
timelock: public(address)
# @notice the last motion id
lastMotionId: public(uint256)
# @notice motions Id => Motion
motions: public(HashMap[uint256, Motion])
# @notice stores if motion with given id has been object from given address
objections: public(HashMap[uint256, HashMap[address, bool]])
# @notice factories addresses => Factory
factories: public(HashMap[address, Factory])
# @notice allowed executors for queued motions
executors: public(HashMap[address, bool])

@external
def __init__(
    governanceToken: address,
    admin: address,
    timelock: address,
    knight: address
):
    """
    @notice
        The constructor sets the initial admin and token address.
    @param governanceToken: The address of the governance token
    @param admin: The address of the admin
    @param timelock: The address of the timelock this contract interacts with
    """

    self.admin = admin
    self.token = governanceToken
    self.timelock = timelock
    self.knight = knight


@external
def createMotion(
    targets: DynArray[address, MAX_POSSIBLE_OPERATIONS],
    values: DynArray[uint256, MAX_POSSIBLE_OPERATIONS],
    signatures: DynArray[String[METHOD_SIG_SIZE], MAX_POSSIBLE_OPERATIONS],
    calldatas: DynArray[Bytes[CALL_DATA_LEN], MAX_POSSIBLE_OPERATIONS]
) -> uint256:
    """
    @notice
        Create a motion to execute a series of transactions.
    @param targets: The addresses of the contracts to call
    @param values: The values to send with the transactions
    @param signatures: The function signatures of the transactions
    @param calldatas: The calldatas of the transactions

    @return motionId: The id of the motion
    """
    assert not self.paused, "!paused"
    assert len(targets) != 0, "!no_targets"
    assert len(targets) <= MAX_POSSIBLE_OPERATIONS, "!too_many_ops"
    assert len(targets) == len(values) and len(targets) == len(signatures) and len(targets) == len(calldatas), "!len_mismatch"
    assert self.factories[msg.sender].isFactory, "!factory"

    self.lastMotionId += 1
    motionId: uint256 = self.lastMotionId

    motionDuration: uint256 = self.factories[msg.sender].motionDuration
    objectionsThreshold: uint256 = self.factories[msg.sender].objectionsThreshold

    motion: Motion = Motion({
        id: motionId,
        proposer: msg.sender,
        targets: targets,
        values: values,
        signatures: signatures,
        calldatas: calldatas,
        timeForQueue: block.timestamp + motionDuration,
        snapshotBlock: block.number,
        objections: 0,
        objectionsThreshold: objectionsThreshold,
        eta: 0,
        isQueued: False
    })

    self.motions[motionId] = motion

    log MotionCreated(
        motionId,
        msg.sender,
        targets,
        values,
        signatures,
        calldatas,
        motion.timeForQueue,
        motion.snapshotBlock,
        objectionsThreshold
    )

    return motionId

@external
def queueMotion(motionId: uint256)-> DynArray[bytes32, MAX_POSSIBLE_OPERATIONS]:
    """
    @notice
        Send motion transactions to be queued in the timelock.
        Queue will fail if operation arguments are repeated or already in timelock queue.
    @param motionId: The id of the motion
    """
    assert not self.paused, "!paused"
    assert self.motions[motionId].id != 0, "!motion_exists"
    assert self.motions[motionId].isQueued == False, "!motion_queued"
    assert self.motions[motionId].timeForQueue <= block.timestamp, "!timeForQueue"

    eta: uint256 = block.timestamp + DualTimelock(self.timelock).leanTrackDelay()

    trxHashes: DynArray[bytes32, MAX_POSSIBLE_OPERATIONS] = []

    numOperations: uint256 = len(self.motions[motionId].targets)
    targets: DynArray[address, MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].targets
    values: DynArray[uint256, MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].values
    signatures: DynArray[String[METHOD_SIG_SIZE], MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].signatures
    calldatas: DynArray[Bytes[CALL_DATA_LEN], MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].calldatas

    for i in range(MAX_POSSIBLE_OPERATIONS):
        if i >= numOperations:
            break
        # check hash doesnt exist already in timelock
        localHash: bytes32 = keccak256(_abi_encode(targets[i], values[i], signatures[i], calldatas[i], eta))
        assert not DualTimelock(self.timelock).queuedRapidTransactions(localHash), "!trxHash_exists"
        trxHash: bytes32 = DualTimelock(self.timelock).queueRapidTransaction(
            targets[i],
            values[i],
            signatures[i],
            calldatas[i],
            eta
        )

        trxHashes.append(trxHash)
    # check motion as queued and set eta
    self.motions[motionId].isQueued = True
    self.motions[motionId].eta = eta

    log MotionQueued(motionId, trxHashes, eta)

    return trxHashes
   
@external
def enactMotion(motionId: uint256):
    """
    @notice
        Enact an already queued motion to execute a series of transactions.
    @param motionId: The id of the motion
    """
    assert not self.paused, "!paused"
    assert self.executors[msg.sender], "!executor"
    assert self.motions[motionId].id != 0, "!motion_exists"
    assert self.motions[motionId].isQueued == True, "!motion_queued"
    assert self.motions[motionId].eta <= block.timestamp, "!eta"

    numOperations: uint256 = len(self.motions[motionId].targets)
    targets: DynArray[address, MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].targets
    values: DynArray[uint256, MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].values
    signatures: DynArray[String[METHOD_SIG_SIZE], MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].signatures
    calldatas: DynArray[Bytes[CALL_DATA_LEN], MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].calldatas
    eta: uint256 = self.motions[motionId].eta

    for i in range(MAX_POSSIBLE_OPERATIONS):
        if i >= numOperations:
            break
        DualTimelock(self.timelock).executeRapidTransaction(
            targets[i],
            values[i],
            signatures[i],
            calldatas[i],
            eta
        )

    # delete motion
    self.motions[motionId] = empty(Motion)

    log MotionEnacted(motionId)

@external
def objectToMotion(motionId: uint256):
    """
    @notice
        Submits an objection to a motion from a "governanceToken" holder with voting power.
    @dev
        The motion must exist.
        The motion must be in the "pending" state.
        The sender must not have already objected.
        The sender must have voting power.
    @param motionId: The id of the motion
    """
    assert self.motions[motionId].id != 0, "!motion_exists"
    assert self.motions[motionId].isQueued == False, "!motion_queued"
    assert self.motions[motionId].timeForQueue > block.timestamp, "!timeForQueue"
    assert not self.objections[motionId][msg.sender], "!already_objected"
    # check voting balance at motion snapshot block and compare to current block number and use the lower one
    snapshotBlock: uint256 = self.motions[motionId].snapshotBlock
    votingBalance: uint256 = min(
        GovToken(self.token).getPriorVotes(msg.sender, snapshotBlock),
        GovToken(self.token).getPriorVotes(msg.sender, block.number)
    )
    assert votingBalance > 0, "!voting_balance"
    totalSupply: uint256 = GovToken(self.token).totalSupplyAt(snapshotBlock)
    newObjectionsAmount: uint256 = self.motions[motionId].objections + votingBalance
    newObjectionsAmountPct: uint256 = (newObjectionsAmount * HUNDRED_PERCENT) / totalSupply
    log MotionObjected(motionId, msg.sender, votingBalance, newObjectionsAmount, newObjectionsAmountPct)

    # update motion objections or delete motion if objections threshold is reached
    if newObjectionsAmountPct >= self.motions[motionId].objectionsThreshold:
        self.motions[motionId] = empty(Motion)
        log MotionRejected(motionId)
    else:
        self.motions[motionId].objections = newObjectionsAmount
        self.objections[motionId][msg.sender] = True

@external
def cancelMotion(motionId: uint256):
    """
    @notice
        Cancels a motion.
    @dev
        The motion must exist.
        The motion must be in the "pending" state.
        The sender must be the proposer of the motion or the guardian role.
    @param motionId: The id of the motion
    """
    # motion: Motion = self.motions[motionId]
    assert self.motions[motionId].id != 0, "!motion_exists"
    # only guardian or proposer can cancel motion
    assert msg.sender == self.knight or msg.sender == self.motions[motionId].proposer, "!access"
   
    # if motion is queued, cancel it in timelock
    if self.motions[motionId].isQueued:
        numOperations: uint256 = len(self.motions[motionId].targets)
        targets: DynArray[address, MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].targets
        values: DynArray[uint256, MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].values
        signatures: DynArray[String[METHOD_SIG_SIZE], MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].signatures
        calldatas: DynArray[Bytes[CALL_DATA_LEN], MAX_POSSIBLE_OPERATIONS] = self.motions[motionId].calldatas
        eta: uint256 = self.motions[motionId].eta
        for i in range(MAX_POSSIBLE_OPERATIONS):
            if i >= numOperations:
                break
            DualTimelock(self.timelock).cancelRapidTransaction(
                targets[i],
                values[i],
                signatures[i],
                calldatas[i],
                eta
            )

    # delete motion
    self.motions[motionId] = empty(Motion)

    log MotionCanceled(motionId)

@external
def addMotionFactory(
    factory: address,
    objectionsThreshold: uint256,
    motionDuration: uint256
):
    """
    @notice
        Add a factory to the list of approved factories.
    @param factory: The address of the factory
    @param objectionsThreshold: The objections threshold for the factory proposed motions
    @param motionDuration: The duration for the factory motions to be queued
    """
    assert msg.sender == self.admin, "!admin"
    assert not self.factories[factory].isFactory, "!factory_exists"
    assert motionDuration >= MIN_MOTION_DURATION, "!motion_duration"
    assert objectionsThreshold >= MIN_OBJECTIONS_THRESHOLD, "!min_objections_threshold"
    assert objectionsThreshold <= MAX_OBJECTIONS_THRESHOLD, "!max_objections_threshold"

    self.factories[factory] = Factory({
        objectionsThreshold: objectionsThreshold,
        motionDuration: motionDuration,
        isFactory: True
    })

    log MotionFactoryAdded(factory, objectionsThreshold, motionDuration)

@external
def removeMotionFactory(factory: address):
    """
    @notice
        Remove a factory from the list of approved factories.
    @param factory: The address of the factory
    """
    assert msg.sender == self.admin, "!admin"
    assert self.factories[factory].isFactory, "!factory_exists"

    self.factories[factory] = empty(Factory)

    log MotionFactoryRemoved(factory)

@external
def addExecutor(executor: address):
    """
    @notice
        Add an executor to the list of approved executors.
    @param executor: The address of the executor
    """
    assert msg.sender == self.admin, "!admin"
    assert not self.executors[executor], "!executor_exists"

    self.executors[executor] = True

    log ExecutorAdded(executor)

@external
def removeExecutor(executor: address):
    """
    @notice
        Remove an executor from the list of approved executors.
    @param executor: The address of the executor
    """
    assert msg.sender == self.admin, "!admin"
    assert self.executors[executor], "!executor_exists"

    self.executors[executor] = False

    log ExecutorRemoved(executor)

@external
def setKnight(knight: address):
    """
    @notice
        Set the knight address.
    @param knight: The address of the knight
    """
    assert msg.sender == self.admin, "!admin"
    assert knight != empty(address), "!knight"

    self.knight = knight

    log KnightSet(knight)

@external
def acceptTimelockAccess():
    """
    @notice
        Accept the access to send trxs to timelock.
    """
    assert msg.sender == self.knight, "!knight"
    DualTimelock(self.timelock).acceptLeanTrack()
    
@external
def pause():
    """
    @notice
        Emergency method to pause the contract. Only knight can pause.
    """
    assert msg.sender == self.knight, "!knight"
    assert not self.paused, "!paused"

    self.paused = True

    log Paused(msg.sender)

@external
def unpause():
    """
    @notice
        Unpause the contract. Only knight or admin can unpause.
    """
    assert msg.sender == self.knight, "!knight"
    assert self.paused, "!unpaused"

    self.paused = False

    log Unpaused(msg.sender)


@external
@view
def canObjectToMotion(motionId: uint256, objector: address) -> bool:
    """
    @notice
        Check if a "governanceToken" holder with voting power can object to a motion.
    @param motionId: The id of the motion
    @param objector: The address of the objector
    @return bool: True if the objector can object to the motion
    """
    if self.motions[motionId].id == 0:
        return False
    if self.motions[motionId].isQueued: # motion is queued
        return False    
    if self.motions[motionId].timeForQueue <= block.timestamp: # motion is expired
        return False
    if self.objections[motionId][objector]: # objector already objected
        return False
    # check voting balance at motion snapshot block and compare to current block number and use the lower one
    votingBalance: uint256 = min(
        GovToken(self.token).getPriorVotes(objector, self.motions[motionId].snapshotBlock),
        GovToken(self.token).getPriorVotes(objector, block.number)
    )
    if votingBalance == 0: # objector has no voting balance
        return False

    return True