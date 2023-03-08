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

admin: public(address)
pendingAdmin: public(address)
token: public(address)


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
