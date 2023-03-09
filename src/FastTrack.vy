# @version 0.3.7

"""
@title Yearn FastTrack an optimistic governance contract
@license GNU AGPLv3
@author yearn.finance
@notice
    A vyper implementation of on-chain voting governance contract for motion proposals and management of smart contract calls.
"""

NAME: constant(String[20]) = "FastTrack"
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
    # @notice The eta for the motion
    eta: uint256
    # @notice The block number at which the motion was created
    snapshotBlock: uint256
    # @notice The number of objections against the motion
    objections: uint256
    # @notice The objection threshold to defeat the motion
    objectionsThreshold: uint256
    # @notice The flag to indicate if the motion has been queued
    queued: bool

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
    eta: uint256
    snapshotBlock: uint256
    objectionThreshold: uint256

### state fields
# @notice The address of the admin
admin: public(address)
# @notice The address of the pending admin
pendingAdmin: public(address)
# @notice The address of the governance token
token: public(address)
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
):
    """
    @notice
        The constructor sets the initial admin and token address.
    @param governanceToken: The address of the governance token
    @param admin: The address of the admin
    """

    self.admin = admin
    self.token = governanceToken


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
        eta: block.timestamp + motionDuration,
        snapshotBlock: block.number,
        objections: 0,
        objectionsThreshold: objectionsThreshold,
        queued: False
    })

    self.motions[motionId] = motion

    log MotionCreated(
        motionId,
        msg.sender,
        targets,
        values,
        signatures,
        calldatas,
        motion.eta,
        motion.snapshotBlock,
        objectionsThreshold
    )

    return motionId


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


