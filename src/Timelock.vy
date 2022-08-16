# @version 0.3.6

"""
@title Yearn Time lock implementation
@license GNU AGPLv3
@author yearn.finance
@notice
    TODO: add notice description
"""

MAX_DATA_LEN: constant(uint256) = 16483
METHOD_SIG_SIZE: constant(uint256) = 1024
DAY: constant(uint256) = 86400
GRACE_PERIOD: constant(uint256) = 14 * DAY
MAXIMUM_DELAY: constant(uint256) = 30 * DAY

event NewAdmin:
    newAdmin: indexed(address)

event NewPendingAdmin:
    newPendingAdmin: indexed(address)

event NewDelay:
    newDelay: indexed(uint256)

event CancelTransaction:
    txHash: indexed(bytes32)
    target: indexed(address)
    value: uint256
    signature: String[METHOD_SIG_SIZE]
    data: Bytes[MAX_DATA_LEN]
    eta: uint256

event ExecuteTransaction:
    txHash: indexed(bytes32)
    target: indexed(address)
    value: uint256
    signature: String[METHOD_SIG_SIZE]
    data: Bytes[MAX_DATA_LEN]
    eta: uint256

event QueueTransaction:
    txHash: indexed(bytes32)
    target: indexed(address)
    value: uint256
    signature: String[METHOD_SIG_SIZE]
    data: Bytes[MAX_DATA_LEN]
    eta: uint256

admin: public(address)
pendingAdmin: public(address)
delay: public(uint256)
queuedTransactions: public(HashMap[bytes32,  bool])


@external
def __init__(admin: address, delay: uint256):
    """
    @dev Deploys the timelock with initial values
    @param admin The contract that rules over the timelock
    @param delay The delay for timelock
    """
    self.admin = admin
    self.delay = delay
