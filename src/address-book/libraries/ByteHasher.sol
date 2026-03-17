// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library ByteHasher {
    /// @dev Creates a keccak256 hash of a bytestring that will always fit in a BN-254 or BabyJubJub field.
    /// @param value The bytestring to hash
    /// @return The hash of the specified value
    /// @dev `>> 8` makes sure that the result is always in the field.
    function hashToField(bytes memory value) internal pure returns (uint256) {
        return uint256(keccak256(value)) >> 8;
    }
}
