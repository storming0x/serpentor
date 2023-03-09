# @version 0.3.7

"""
@title Yearn Dual Time lock implementation
@license GNU AGPLv3
@author yearn.finance
@notice
    A timelock contract implementation in vyper that manages two queues with different delay configurations. 
    The first queue is for governance actions compatible with other governor type systems, and the second queue is for faster operational actions.
    The operational actions will be used for actions that are not critical to the protocol, but are still
    time sensitive. The governance actions will be used for actions that are critical to the protocol, 
    and require a larger delay.
    Designed to work with most governance voting contracts and close integration
    with SerpentorBravo.
    The second queue for operational actions is used for fast tracking actions that are generated by pre-approved contracts
    with limited access and very specific functionality.
"""

event NewAdmin:
    newAdmin: indexed(address)

event NewFastTrack:
    newFastTrack: indexed(address)

event NewPendingAdmin:
    newPendingAdmin: indexed(address)

event NewPendingFastTrack:
    newPendingFastTrack: indexed(address)

event NewDelay:
    newDelay: uint256

event NewFastTrackDelay:
    newFastTrackDelay: uint256

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

event QueueFastTransaction:
    txHash: indexed(bytes32)
    target: indexed(address)
    value: uint256
    signature: String[METHOD_SIG_SIZE]
    data: Bytes[CALL_DATA_LEN]
    eta: uint256

event CancelFastTransaction:
    txHash: indexed(bytes32)
    target: indexed(address)
    value: uint256
    signature: String[METHOD_SIG_SIZE]
    data: Bytes[CALL_DATA_LEN]
    eta: uint256

event ExecuteFastTransaction:
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

fastTrack: public(address)
pendingFastTrack: public(address)
fastTrackDelay: public(uint256)
queuedFastTransactions: public(HashMap[bytes32,  bool])

@external
def __init__(admin: address, fastTrack: address, delay: uint256, fastTrackDelay: uint256):
    """
    @notice Deploys the timelock with initial values
    @param admin The contract that rules over the timelock
    @param fastTrack The contract that rules over the fast track queued transactions. Can be 0x0.
    @param delay The delay for timelock
    @param fastTrackDelay The delay for fast track timelock
    """

    assert delay >= MINIMUM_DELAY, "Delay must exceed minimum delay"
    assert delay <= MAXIMUM_DELAY, "Delay must not exceed maximum delay"
    assert delay > fastTrackDelay, "Delay must be greater than fast track delay"
    assert admin != empty(address), "!admin"
    self.admin = admin
    self.fastTrack = fastTrack
    self.delay = delay
    self.fastTrackDelay = fastTrackDelay


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
def setFastTrackDelay(fastTrackDelay: uint256):
    """
    @notice
        Updates fast track delay to new value
    @param fastTrackDelay The delay for fast track timelock
    """
    assert msg.sender == self, "!Timelock"
    assert fastTrackDelay < self.delay, "!fastTrackDelay < delay"
    self.fastTrackDelay = fastTrackDelay

    log NewFastTrackDelay(fastTrackDelay)

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
def acceptFastTrack():
    """
    @notice
        updates `pendingFastTrack` to fastTrack.
        msg.sender must be `pendingFastTrack`
    """
    assert msg.sender == self.pendingFastTrack, "!pendingFastTrack"
    self.fastTrack = msg.sender
    self.pendingFastTrack = empty(address)
    log NewFastTrack(msg.sender)
    log NewPendingFastTrack(empty(address))
    

@external
def setPendingFastTrack(pendingFastTrack: address):
    """
    @notice
       Updates `pendingFastTrack` value
       msg.sender must be this contract
    @param pendingFastTrack The proposed new fast track contract for the contract
    """
    assert msg.sender == self, "!Timelock"
    self.pendingFastTrack = pendingFastTrack

    log NewPendingFastTrack(pendingFastTrack)

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
    @param target The address of the contract to execute
    @param amount The amount of ether to send to the contract
    @param signature The signature of the function to execute
    @param data The data to send to the contract
    @param eta The timestamp when the transaction can be executed

    @return txHash The hash of the transaction
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
    @param target The address of the contract to execute
    @param amount The amount of ether to send to the contract
    @param signature The signature of the function to execute
    @param data The data to send to the contract
    @param eta The timestamp when the transaction can be executed
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
    @param target The address of the contract to execute
    @param amount The amount of ether to send to the contract
    @param signature The signature of the function to execute
    @param data The data to send to the contract
    @param eta The timestamp when the transaction can be executed

    @return response The response from the transaction
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
def queueFastTransaction(
    target: address,
    amount: uint256,
    signature: String[METHOD_SIG_SIZE],
    data: Bytes[CALL_DATA_LEN],
    eta: uint256
) -> bytes32:
    """
    @notice
        adds transaction to fast execution queue
        fast execution queue cannot target this timelock contract
    @param target The address of the contract to execute
    @param amount The amount of ether to send to the contract
    @param signature The signature of the function to execute
    @param data The data to send to the contract
    @param eta The timestamp when the transaction can be executed

    @return txHash The hash of the transaction
    """
    # @dev minor gas savings
    fastTrack: address = self.fastTrack
    assert msg.sender == fastTrack, "!fastTrack"
    assert target != fastTrack, "!target"
    assert target != self, "!target"
    assert target != self.admin, "!target"
    assert eta >= block.timestamp + self.fastTrackDelay, "!eta"

    trxHash: bytes32 = keccak256(_abi_encode(target, amount, signature, data, eta))
    self.queuedFastTransactions[trxHash] = True

    log QueueFastTransaction(trxHash, target, amount, signature, data, eta)

    return trxHash

@external
def cancelFastTransaction(
    target: address,
    amount: uint256,
    signature: String[METHOD_SIG_SIZE],
    data: Bytes[CALL_DATA_LEN],
    eta: uint256
):
    """
    @notice
        cancels a queued fast transaction
    @param target The address of the contract to execute
    @param amount The amount of ether to send to the contract
    @param signature The signature of the function to execute
    @param data The data to send to the contract
    @param eta The timestamp when the transaction can be executed
    """
    assert msg.sender == self.fastTrack, "!fastTrack"

    trxHash: bytes32 = keccak256(_abi_encode(target, amount, signature, data, eta))
    self.queuedFastTransactions[trxHash] = False

    log CancelFastTransaction(trxHash, target, amount, signature, data, eta)

@payable
@external
def executeFastTransaction(
    target: address,
    amount: uint256,
    signature: String[METHOD_SIG_SIZE],
    data: Bytes[CALL_DATA_LEN],
    eta: uint256
) -> Bytes[MAX_DATA_LEN]:
    """
    @notice
        executes a queued fast transaction
    @param target The address of the contract to execute
    @param amount The amount of ether to send to the contract
    @param signature The signature of the function to execute
    @param data The data to send to the contract
    @param eta The timestamp when the transaction can be executed

    @return response The response from the transaction
    """
    assert msg.sender == self.fastTrack, "!fastTrack"

    trxHash: bytes32 = keccak256(_abi_encode(target, amount, signature, data, eta))
    assert self.queuedFastTransactions[trxHash], "!queued_trx"
    assert block.timestamp >= eta, "!eta"
    assert block.timestamp <= eta + GRACE_PERIOD, "!staled_trx"

    self.queuedFastTransactions[trxHash] = False

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

    log ExecuteFastTransaction(trxHash, target, amount, signature, data, eta)

    return response


@external
@view
def GRACE_PERIOD() -> uint256:
    return GRACE_PERIOD