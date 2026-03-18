// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IWIP101} from "./interfaces/IWIP101.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract WIP101Example is IWIP101, ERC165 {
    // bytes4(keccak256("verifyRpRequest(uint8,uint256,uint64,uint64,uint256)"))
    bytes4 internal constant MAGICVALUE = 0xc97c0bca;

    uint8 internal constant EXPECTED_VERSION = 1;

    uint256 constant EXPECTED_ACTION = uint256(keccak256(abi.encodePacked("vote1", uint64(3)))) >> 8;

    mapping(uint256 => bool) public usedNonces;

    // @inheritdoc IWIP101
    function verifyRpRequest(uint8 version, uint256 nonce, uint64 createdAt, uint64 expiresAt, uint256 action)
        external
        view
        returns (bytes4 magicValue)
    {
        if (version != EXPECTED_VERSION) {
            revert InvalidRequest();
        }

        if (usedNonces[nonce]) {
            revert InvalidRequest();
        }

        if (createdAt > block.timestamp || createdAt > block.timestamp - 15 minutes) {
            revert InvalidRequest();
        }

        if (expiresAt > block.timestamp + 15 minutes) {
            revert InvalidRequest();
        }

        if (action != EXPECTED_ACTION) {
            revert InvalidRequest();
        }

        return MAGICVALUE;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IWIP101).interfaceId;
    }

    /**
     * @dev This would be the action that consumes and verifies the World ID Proof, we invalidate the nonce.
     * @param nonce The used nonce
     */
    function executeAction(uint256 nonce) external {
        usedNonces[nonce] = true;
    }
}
