# @version 0.3.6

"""
@title Yearn Time lock implementation
@license GNU AGPLv3
@author yearn.finance
@notice
    TODO: add notice description
"""

MAX_DATA_LEN: constant(uint256) = 16608
CALL_DATA_LEN: constant(uint256) = 16483
METHOD_SIG_SIZE: constant(uint256) = 1024
DAY: constant(uint256) = 86400
GRACE_PERIOD: constant(uint256) = 14 * DAY
MINIMUM_DELAY: constant(uint256) = 2 * DAY
MAXIMUM_DELAY: constant(uint256) = 30 * DAY

event Newqueen:
    newqueen: indexed(address)

event NewPendingqueen:
    newPendingqueen: indexed(address)

event NewDelay:
    newDelay: indexed(uint256)

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
    @dev Deploys the timelock with initial values
    @param queen The contract that rules over the timelock
    @param delay The delay for timelock
    """

    assert delay >= MINIMUM_DELAY, "Delay must exceed minimum delay"
    assert delay <= MAXIMUM_DELAY, "Delay must not exceed maximum delay"
    self.queen = queen
    self.delay = delay

@external
def setDelay(delay: uint256):
    """
    @notice
        Updates delay to new value
    @dev
    @param delay The delay for timelock
    """
    assert msg.sender == self, "!Timelock"
    assert delay >= MINIMUM_DELAY, "!MINIMUM_DELAY"
    assert delay <= MAXIMUM_DELAY, "!MAXIMUM_DELAY"
    self.delay = delay

    log NewDelay(delay)

@external
def acceptQueen():
    """
    @notice
        updates `pendingQueen` to queen.
        msg.sender must be `pendingQueen`
    """
    assert msg.sender == self.pendingQueen, "!pendingQueen"
    self.queen = msg.sender
    self.pendingQueen = empty(address)

    log Newqueen(msg.sender)

@external
def setPendingqueen(pendingQueen: address):
    """
    @notice
       Updates `pendingQueen` value
       msg.sender must be this contract
    @dev
    @param pendingQueen The proposed new queen for the contract
    """
    assert msg.sender == self, "!Timelock"
    self.pendingQueen = pendingQueen

    log NewPendingqueen(pendingQueen)

@external
def queuedTransaction(target: address, amount: uint256, signature: String[METHOD_SIG_SIZE], data: Bytes[CALL_DATA_LEN], eta: uint256) -> bytes32:
    """
    @notice
    @dev
    @param 
    """
    assert msg.sender == self, "!queen"
    assert eta >= block.timestamp + self.delay, "!eta"

    txHash: bytes32 = keccak256(_abi_encode(target, amount, signature, data, eta))
    self.queuedTransactions[txHash] = True

    log QueueTransaction(txHash, target, amount, signature, data, eta)

    return txHash

@external
def cancelTransaction(target: address, amount: uint256, signature: String[METHOD_SIG_SIZE], data: Bytes[CALL_DATA_LEN], eta: uint256):
    """
    @notice
    @dev
    @param 
    """
    assert msg.sender == self, "!queen"

    txHash: bytes32 = keccak256(_abi_encode(target, amount, signature, data, eta))
    self.queuedTransactions[txHash] = False

    log CancelTransaction(txHash, target, amount, signature, data, eta)

@external
def executeTransaction(target: address, amount: uint256, signature: String[METHOD_SIG_SIZE], data: Bytes[CALL_DATA_LEN], eta: uint256) -> Bytes[MAX_DATA_LEN]:
    """
    @notice
    @dev
    @param 
    """
    assert msg.sender == self, "!queen"

    txHash: bytes32 = keccak256(_abi_encode(target, amount, signature, data, eta))
    assert self.queuedTransactions[txHash], "!queued_trx"
    assert block.timestamp >= eta, "!Timelock"
    assert block.timestamp <= eta + GRACE_PERIOD, "!staled_trx"

    self.queuedTransactions[txHash] = False

    # @dev reference: https://github.com/compound-finance/compound-protocol/blob/a3214f67b73310d547e00fc578e8355911c9d376/contracts/Timelock.sol#L96
    # TODO: check if this is the correct code for vyper based on solidity
    callData: Bytes[MAX_DATA_LEN] = b""

    if len(signature) == 0:
        # @dev use provided data directly
        callData = data
    else: 
        # @dev use signature + data
        sig_hash: bytes32 = keccak256(signature)
        func_sig: bytes4 = convert(sig_hash, bytes4)
        callData = _abi_encode(func_sig, data)

    success: bool = False
    response: Bytes[32] = b""

    success, response = raw_call(
        target,
        callData,
        max_outsize=32,
        value=amount,
        revert_on_failure=False
    )

    assert success, "!trx_revert"

    log ExecuteTransaction(txHash, target, amount, signature, data, eta)

    return callData
