# @version 0.3.7

"""
@title Yearn LeanTrack an optimistic governance contract
@license GNU AGPLv3
@author yearn.finance
@notice
    A vyper implementation of on-chain voting governance contract for motion proposals and management of smart contract calls.
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
MIN_MOTION_DURATION: constant(uint256) = 57600 # 16 hours


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
    # @notice The block.timestamp when the motion can be queued to timelock
    timeForQueue: uint256
    # @notice The block number at which the motion was created
    snapshotBlock: uint256
    # @notice The number of objections against the motion
    objections: uint256
    # @notice The objection threshold to defeat the motion
    objectionsThreshold: uint256


# ///// EVENTS /////
event MotionFactoryAdded:
    factory: indexed(address)
    objectionThreshold: uint256
    motionDuration: uint256    

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


### state fields
# @notice The address of the admin
admin: public(address)
# @notice The address of the pending admin
pendingAdmin: public(address)
# @notice The address of the guardian role
knight: public(address)
# @notice The address of the governance token
token: public(address)
# @notice The address of the timelock
timelock: public(address)
# @notice the last motion id
lastMotionId: public(uint256)
# @notice motions Id => Motion
motions: public(HashMap[uint256, Motion])
# @notice factories addresses => Factory
factories: public(HashMap[address, Factory])

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
    assert len(targets) != 0, "!no_targets"
    assert len(targets) <= MAX_POSSIBLE_OPERATIONS, "!too_many_ops"
    assert len(targets) == len(values) and len(targets) == len(signatures) and len(targets) == len(calldatas), "!len_mismatch"
    assert self.factories[msg.sender].isFactory, "!factory"

    # TODO: add motions limit check

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
        objectionsThreshold: objectionsThreshold
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
        Queue a motion to execute a series of transactions.
    @param motionId: The id of the motion
    """
    motion: Motion = self.motions[motionId]
    assert motion.id != 0, "!motion_exists"
    assert motion.timeForQueue <= block.timestamp, "!timeForQueue"
 
    eta: uint256 = block.timestamp + DualTimelock(self.timelock).leanTrackDelay()

    trxHashes: DynArray[bytes32, MAX_POSSIBLE_OPERATIONS] = []

    numOperations: uint256 = len(motion.targets)
    
    for i in range(MAX_POSSIBLE_OPERATIONS):
        if i >= numOperations:
            break
        trxHash: bytes32 = DualTimelock(self.timelock).queueRapidTransaction(
            motion.targets[i],
            motion.values[i],
            motion.signatures[i],
            motion.calldatas[i],
            eta
        )

        trxHashes.append(trxHash)
    # remove motion from the mapping
    self.motions[motionId] = empty(Motion)
    
    log MotionQueued(motionId, trxHashes, eta)

    return trxHashes
   


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
def acceptTimelockAccess():
    """
    @notice
        Accept the access to send trxs to timelock.
    """
    assert msg.sender == self.knight, "!knight"
    DualTimelock(self.timelock).acceptLeanTrack()
    