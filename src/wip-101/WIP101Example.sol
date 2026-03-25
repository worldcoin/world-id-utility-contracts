// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IWIP101} from "./interfaces/IWIP101.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract WIP101Example is IWIP101, ERC165 {
    // bytes4(keccak256("verifyRpRequest(uint8,uint256,uint64,uint64,uint256,bytes)"))
    bytes4 internal constant MAGICVALUE = 0x35dbc8de;

    uint8 internal constant EXPECTED_VERSION = 1;

    uint8 internal constant EXPECTED_ACTION_ATTR = 3;

    mapping(uint256 => bool) public usedNonces;

    // @inheritdoc IWIP101
    function verifyRpRequest(
        uint8 version,
        uint256 nonce,
        uint64 createdAt,
        uint64 expiresAt,
        uint256 action,
        bytes calldata data
    ) external view returns (bytes4 magicValue) {
        if (version != EXPECTED_VERSION) {
            revert InvalidRequest(100);
        }

        if (usedNonces[nonce]) {
            revert InvalidRequest(101);
        }

        if (createdAt > block.timestamp || createdAt < block.timestamp - 15 minutes) {
            revert InvalidRequest(102);
        }

        if (expiresAt < block.timestamp || expiresAt > block.timestamp + 15 minutes) {
            revert InvalidRequest(103);
        }

        // This is an example of how we'd use the arbitrary data to perform more comprehensive checks
        if (uint8(data[0]) != EXPECTED_ACTION_ATTR) {
            revert InvalidRequest(104);
        }

        uint256 expected_action = uint256(keccak256(abi.encodePacked("vote1", data))) >> 8;

        if (action != expected_action) {
            revert InvalidRequest(105);
        }

        return MAGICVALUE;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IWIP101).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev This would be the action that consumes and verifies the World ID Proof, after the proof
     * is verified, we invalidate the nonce. Note this would normally verify the proof which prevents DDoS
     * on nonces.
     * @param nonce The used nonce
     */
    function executeAction(uint256 nonce) external {
        usedNonces[nonce] = true;
    }
}
