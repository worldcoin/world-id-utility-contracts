// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @dev Interface of the WIP-101 standard for World ID,
 *   RP Signature Verification Method for Smart Contracts.
 */
interface IWIP101 is IERC165 {
    error InvalidRequest();

    /**
     * @notice Verifies a World ID Proof Request is authorized by the RP.
     * @dev Should return whether the RP request is valid and should be honored.
     * @param version The version determines the format of the signature
     * @param nonce Unique nonce for this request
     * @param createdAt Creation timestamp of the request
     * @param expiresAt Expiration timestamp specified for the request
     * @param action Provided action for the request. Importantly, this is already a hashed
     *  action as a field element.
     */
    function verifyRpRequest(uint8 version, uint256 nonce, uint64 createdAt, uint64 expiresAt, uint256 action)
        external
        view
        returns (bytes4 magicValue);
}
