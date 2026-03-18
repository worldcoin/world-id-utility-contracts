// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @dev Interface of the WIP-101 standard for World ID,
 *   RP Signature Verification Method for Smart Contracts.
 */
interface IWIP101 is IERC165 {
    /**
     * @dev The RP request is not valid.
     */
    error InvalidRequest();

    /**
     * @notice Verifies a World ID Proof Request is authorized by the RP.
     * @dev Should return whether the RP request is valid and should be honored.
     * @param version The version determines the format of the signature
     * @param nonce Unique nonce for this request
     * @param createdAt Creation timestamp of the request
     * @param expiresAt Expiration timestamp specified for the request
     * @param action Provided action for the request. Importantly, this is already a hashed
     * @param data Arbitrary data useful for the verification.
     *  action as a field element.
     * @return magicValue The expected magic value when the signature is valid. Reverts otherwise.
     */
    function verifyRpRequest(
        uint8 version,
        uint256 nonce,
        uint64 createdAt,
        uint64 expiresAt,
        uint256 action,
        bytes calldata data
    ) external view returns (bytes4 magicValue);
}
