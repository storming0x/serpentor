# @version 0.3.7

"""
@title Yearn Time lock implementation
@license GNU AGPLv3
@author yearn.finance
@notice
    A timelock contract implementation in vyper. Designed to work with close integration
    with SerpentorBravo, a governance contract for on-chain voting of proposals and execution.
"""

MAX_DATA_LEN: constant(uint256) = 16608
CALL_DATA_LEN: constant(uint256) = 16483
METHOD_SIG_SIZE: constant(uint256) = 1024
DAY: constant(uint256) = 86400
GRACE_PERIOD: constant(uint256) = 14 * DAY
MINIMUM_DELAY: constant(uint256) = 2 * DAY
MAXIMUM_DELAY: constant(uint256) = 30 * DAY

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


event NewQueen:
    newQueen: indexed(address)

event NewPendingQueen:
    newPendingqueen: indexed(address)

event NewDelay:
    newDelay: uint256

event CancelTransaction:
    txHash: indexed(bytes32)
    target: indexed(address)
    value: uint256
    signature: String[METHOD_SIG_SIZE]
    data: Bytes[CALL_DATA_LEN]
    eta: uint256

event ExecuteTransaction:
    txHash: indexed(bytes32)
    target: indexed(address)
    value: uint256
    signature: String[METHOD_SIG_SIZE]
    data: Bytes[CALL_DATA_LEN]
    eta: uint256

event QueueTransaction:
    txHash: indexed(bytes32)
    target: indexed(address)
    value: uint256
    signature: String[METHOD_SIG_SIZE]
    data: Bytes[CALL_DATA_LEN]
    eta: uint256

queen: public(address)
pendingQueen: public(address)
delay: public(uint256)
queuedTransactions: public(HashMap[bytes32,  bool])


@external
def __init__(queen: address, delay: uint256):
    """
    @notice Deploys the timelock with initial values
    @param queen The contract that rules over the timelock
    @param delay The delay for timelock
    """

    assert delay >= MINIMUM_DELAY, "Delay must exceed minimum delay"
    assert delay <= MAXIMUM_DELAY, "Delay must not exceed maximum delay"
    assert queen != empty(address), "!queen"
    self.queen = queen
    self.delay = delay

@external
@payable
def __default__():
    pass

@external
def setDelay(delay: uint256):
    """
    @notice
        Updates delay to new value
    @param delay The delay for timelock
    """
    assert msg.sender == self, "!Timelock"
    assert delay >= MINIMUM_DELAY, "!MINIMUM_DELAY"
    assert delay <= MAXIMUM_DELAY, "!MAXIMUM_DELAY"
    self.delay = delay

    log NewDelay(delay)

@external
def acceptThrone():
    """
    @notice
        updates `pendingQueen` to queen.
        msg.sender must be `pendingQueen`
    """
    assert msg.sender == self.pendingQueen, "!pendingQueen"
    self.queen = msg.sender
    self.pendingQueen = empty(address)

    log NewQueen(msg.sender)

@external
def setPendingQueen(pendingQueen: address):
    """
    @notice
       Updates `pendingQueen` value
       msg.sender must be this contract
    @param pendingQueen The proposed new queen for the contract
    """
    assert msg.sender == self, "!Timelock"
    self.pendingQueen = pendingQueen

    log NewPendingQueen(pendingQueen)

@external
def queueTransaction(trx: Transaction) -> bytes32:
    """
    @notice
        adds transaction to execution queue
    @param trx Transaction to queue
    """
    assert msg.sender == self.queen, "!queen"
    assert trx.eta >= block.timestamp + self.delay, "!eta"

    trxHash: bytes32 = keccak256(_abi_encode(trx.target, trx.amount, trx.signature, trx.callData, trx.eta))
    self.queuedTransactions[trxHash] = True

    log QueueTransaction(trxHash, trx.target, trx.amount, trx.signature, trx.callData, trx.eta)

    return trxHash

@external
def cancelTransaction(trx: Transaction):
    """
    @notice
        cancels a queued transaction
    @param trx Transaction to cancel
    """
    assert msg.sender == self.queen, "!queen"

    trxHash: bytes32 = keccak256(_abi_encode(trx.target, trx.amount, trx.signature, trx.callData, trx.eta))
    self.queuedTransactions[trxHash] = False

    log CancelTransaction(trxHash, trx.target, trx.amount, trx.signature, trx.callData, trx.eta)

@payable
@external
def executeTransaction(trx: Transaction) -> Bytes[MAX_DATA_LEN]:
    """
    @notice
        executes a queued transaction
    @param trx Transaction to execute
    """
    assert msg.sender == self.queen, "!queen"

    trxHash: bytes32 = keccak256(_abi_encode(trx.target, trx.amount, trx.signature, trx.callData, trx.eta))
    assert self.queuedTransactions[trxHash], "!queued_trx"
    assert block.timestamp >= trx.eta, "!eta"
    assert block.timestamp <= trx.eta + GRACE_PERIOD, "!staled_trx"

    self.queuedTransactions[trxHash] = False

    callData: Bytes[MAX_DATA_LEN] = b""

    if len(trx.signature) == 0:
        # @dev use provided data directly
        callData = trx.callData
    else: 
        # @dev use signature + data
        sig_hash: bytes32 = keccak256(trx.signature)
        func_sig: bytes4 = convert(slice(sig_hash, 0, 4), bytes4)
        callData = concat(func_sig, trx.callData)

    success: bool = False
    response: Bytes[MAX_DATA_LEN] = b""

    success, response = raw_call(
        trx.target,
        callData,
        max_outsize=MAX_DATA_LEN,
        value=trx.amount,
        revert_on_failure=False
    )

    assert success, "!trx_revert"

    log ExecuteTransaction(trxHash, trx.target, trx.amount, trx.signature, trx.callData, trx.eta)

    return response


@external
@view
def GRACE_PERIOD() -> uint256:
    return GRACE_PERIOD