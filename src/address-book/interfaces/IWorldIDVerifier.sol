// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IWorldIDVerifier
 * @notice Minimal verifier interface consumed by AddressBook.
 */
interface IWorldIDVerifier {
    /**
     * @notice Verifies a World ID uniqueness proof.
     * @param nullifier The nullifier output from the proof.
     * @param action The action input bound into the proof.
     * @param rpId The relying-party identifier.
     * @param nonce The request nonce.
     * @param signalHash The signal hash public input.
     * @param expiresAtMin The credential minimum expiration public input.
     * @param issuerSchemaId The credential issuer schema identifier.
     * @param credentialGenesisIssuedAtMin The minimum credential genesis issuance timestamp.
     * @param zeroKnowledgeProof The encoded proof data with Merkle root.
     */
    function verify(
        uint256 nullifier,
        uint256 action,
        uint64 rpId,
        uint256 nonce,
        uint256 signalHash,
        uint64 expiresAtMin,
        uint64 issuerSchemaId,
        uint256 credentialGenesisIssuedAtMin,
        uint256[5] calldata zeroKnowledgeProof
    ) external view;
}
