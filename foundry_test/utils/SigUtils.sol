// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    // keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)');
    bytes32 public constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // keccak256("Ballot(uint256 proposalId,uint8 support)")
    bytes32 public constant BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support)");



    struct Ballot {
        uint256 proposalId;
        uint8 support;
    }

    // computes the hash of a permit
    function getStructHash(Ballot memory _ballot)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    BALLOT_TYPEHASH,
                    _ballot.proposalId,
                    _ballot.support
                )
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(Ballot memory _ballot)
        public
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getStructHash(_ballot)
                )
            );
    }
}
