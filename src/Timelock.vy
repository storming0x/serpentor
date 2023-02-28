# @version 0.3.7

"""
@title Yearn Time lock implementation
@license GNU AGPLv3
@author yearn.finance
@notice
    A timelock contract implementation in vyper. Designed to work with most governance voting contracts and close integration
    with SerpentorBravo, a governance contract for on-chain voting of proposals and execution.
"""

event NewAdmin:
    newAdmin: indexed(address)

event NewPendingAdmin:
    newPendingAdmin: indexed(address)

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

MAX_DATA_LEN: constant(uint256) = 16608
CALL_DATA_LEN: constant(uint256) = 16483
METHOD_SIG_SIZE: constant(uint256) = 1024
DAY: constant(uint256) = 86400
GRACE_PERIOD: constant(uint256) = 14 * DAY
MINIMUM_DELAY: constant(uint256) = 2 * DAY
MAXIMUM_DELAY: constant(uint256) = 30 * DAY

admin: public(address)
pendingAdmin: public(address)
delay: public(uint256)
queuedTransactions: public(HashMap[bytes32,  bool])

@external
def __init__(admin: address, delay: uint256):
    """
    @notice Deploys the timelock with initial values
    @param admin The contract that rules over the timelock
    @param delay The delay for timelock
    """

    assert delay >= MINIMUM_DELAY, "Delay must exceed minimum delay"
    assert delay <= MAXIMUM_DELAY, "Delay must not exceed maximum delay"
    assert admin != empty(address), "!admin"
    self.admin = admin
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
def acceptAdmin():
    """
    @notice
        updates `pendingAdmin` to admin.
        msg.sender must be `pendingAdmin`
    """
    assert msg.sender == self.pendingAdmin, "!pendingAdmin"
    self.admin = msg.sender
    self.pendingAdmin = empty(address)

    log NewAdmin(msg.sender)
    log NewPendingAdmin(empty(address))

@external
def setPendingAdmin(pendingAdmin: address):
    """
    @notice
       Updates `pendingAdmin` value
       msg.sender must be this contract
    @param pendingAdmin The proposed new admin for the contract
    """
    assert msg.sender == self, "!Timelock"
    self.pendingAdmin = pendingAdmin

    log NewPendingAdmin(pendingAdmin)

@external
def queueTransaction(
    target: address,
    amount: uint256,
    signature: String[METHOD_SIG_SIZE],
    data: Bytes[CALL_DATA_LEN],
    eta: uint256
) -> bytes32:
    """
    @notice
        adds transaction to execution queue
    @param trx Transaction to queue
    """
    assert msg.sender == self.admin, "!admin"
    assert eta >= block.timestamp + self.delay, "!eta"

    trxHash: bytes32 = keccak256(_abi_encode(target, amount, signature, data, eta))
    self.queuedTransactions[trxHash] = True

    log QueueTransaction(trxHash, target, amount, signature, data, eta)

    return trxHash

@external
def cancelTransaction(
    target: address,
    amount: uint256,
    signature: String[METHOD_SIG_SIZE],
    data: Bytes[CALL_DATA_LEN],
    eta: uint256
):
    """
    @notice
        cancels a queued transaction
    @param trx Transaction to cancel
    """
    assert msg.sender == self.admin, "!admin"

    trxHash: bytes32 = keccak256(_abi_encode(target, amount, signature, data, eta))
    self.queuedTransactions[trxHash] = False

    log CancelTransaction(trxHash, target, amount, signature, data, eta)

@payable
@external
def executeTransaction(
    target: address,
    amount: uint256,
    signature: String[METHOD_SIG_SIZE],
    data: Bytes[CALL_DATA_LEN],
    eta: uint256
) -> Bytes[MAX_DATA_LEN]:
    """
    @notice
        executes a queued transaction
    @param trx Transaction to execute
    """
    assert msg.sender == self.admin, "!admin"

    trxHash: bytes32 = keccak256(_abi_encode(target, amount, signature, data, eta))
    assert self.queuedTransactions[trxHash], "!queued_trx"
    assert block.timestamp >= eta, "!eta"
    assert block.timestamp <= eta + GRACE_PERIOD, "!staled_trx"

    self.queuedTransactions[trxHash] = False

    callData: Bytes[MAX_DATA_LEN] = b""

    if len(signature) == 0:
        # @dev use provided data directly
        callData = data
    else: 
        # @dev use signature + data
        sig_hash: bytes32 = keccak256(signature)
        func_sig: bytes4 = convert(slice(sig_hash, 0, 4), bytes4)
        callData = concat(func_sig, data)

    success: bool = False
    response: Bytes[MAX_DATA_LEN] = b""

    success, response = raw_call(
        target,
        callData,
        max_outsize=MAX_DATA_LEN,
        value=amount,
        revert_on_failure=False
    )

    assert success, "!trx_revert"

    log ExecuteTransaction(trxHash, target, amount, signature, data, eta)

    return response


@external
@view
def GRACE_PERIOD() -> uint256:
    return GRACE_PERIOD