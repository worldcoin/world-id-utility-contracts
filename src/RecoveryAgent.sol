// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Recovery Agent
 * @author World Contributors
 * @notice A very simple implementation of a signing contract where an owner can authorize multiple signers to sign on their behalf without management privileges.
 * @dev This contract is used as a Recovery Agent in the World ID Protocol.
 * @custom:repo https://github.com/worldcoin/world-id-utility-contracts
 */
contract RecoveryAgent is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IERC1271 {
    using EnumerableSet for EnumerableSet.AddressSet;
    ////////////////////////////////////////////////////////////
    //                         Events                         //
    ////////////////////////////////////////////////////////////

    /// @notice Emitted when a signer is added to the authorized set.
    event SignerAdded(address indexed signer);

    /// @notice Emitted when a signer is removed from the authorized set.
    event SignerRemoved(address indexed signer);

    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    /// @dev Thrown when a function is called on an uninitialized implementation.
    error ImplementationNotInitialized();

    /// @dev Thrown when attempting to set an address parameter to the zero address.
    error ZeroAddress();

    /// @dev Thrown when attempting to add a signer that is already authorized.
    error SignerAlreadyAuthorized(address signer);

    /// @dev Thrown when attempting to operate on a signer which is not authorized.
    error SignerNotAuthorized(address signer);

    /// @dev Thrown when attempting to renounce ownership, which is disabled for this contract.
    error RenounceOwnershipDisabled();

    ////////////////////////////////////////////////////////////
    //                        Modifiers                       //
    ////////////////////////////////////////////////////////////

    /// @notice Ensures the implementation has been initialized (via proxy initialization).
    /// @dev Reverts if `_getInitializedVersion() == 0`.
    modifier onlyInitialized() {
        _onlyInitialized();
        _;
    }

    /// @dev Reverts if the contract is not initialized.
    function _onlyInitialized() internal view virtual {
        if (_getInitializedVersion() == 0) {
            revert ImplementationNotInitialized();
        }
    }

    ////////////////////////////////////////////////////////////
    //                        Constants                       //
    ////////////////////////////////////////////////////////////

    // @dev ERC-1271 magic value https://eips.ethereum.org/EIPS/eip-1271
    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 internal constant _MAGICVALUE = 0x1626ba7e;

    ////////////////////////////////////////////////////////////
    //                        Members                         //
    ////////////////////////////////////////////////////////////

    // DO NOT REORDER! To ensure compatibility between upgrades, it is exceedingly important
    // that no reordering of these variables takes place. If reordering happens, a storage
    // clash will occur (effectively a memory safety error).

    /// @dev The set of authorized signers that can sign on behalf of the contract.
    EnumerableSet.AddressSet internal _signers;

    ////////////////////////////////////////////////////////////
    //                       Constructor                      //
    ////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) public virtual initializer {
        __Ownable_init(owner); // `OwnableUpgradeable` delegation
        __Ownable2Step_init();
    }

    ////////////////////////////////////////////////////////////
    //                  Public View Functions                 //
    ////////////////////////////////////////////////////////////

    /**
     * @dev Returns whether the signature is authorized for a given hash. This function will revert if the signature is invalid.
     * @param hash Hash of the data to be signed. This is usually an EIP-712 typed data signature.
     * @param signature Signature byte array associated with `hash`
     * @custom:example Digest hash
     *
     *  ```
     *  bytes32 messageHash = _hashTypedDataV4(
     *        keccak256(abi.encode(
     *            RECOVER_ACCOUNT_TYPEHASH,
     *            leafIndex,
     *            newAuthenticatorAddress,
     *            newAuthenticatorPubkey,
     *            newOffchainSignerCommitment,
     *            nonce
     *        ))
     *    )
     *  ```
     */
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        virtual
        onlyProxy
        onlyInitialized
        returns (bytes4 magicValue)
    {
        // Extract the signer from the signature and check if they are an authorized signer
        address signer = ECDSA.recover(hash, signature);
        if (_signers.contains(signer)) {
            return _MAGICVALUE;
        }
        revert SignerNotAuthorized(signer);
    }

    /**
     * @dev Checks whether a specific address is authorized to sign on behalf of the contract.
     * @param signer The address being checked
     */
    function isAuthorizedSigner(address signer) external view virtual onlyProxy onlyInitialized returns (bool) {
        return _signers.contains(signer);
    }

    /**
     * @dev The number of authorized signers to sign on behalf of the contract.
     */
    function signerCount() external view virtual onlyProxy onlyInitialized returns (uint256) {
        return _signers.length();
    }

    /**
     * @dev Gets the signer address at a specific index.
     * @param index The index of the signer to retrieve (between 0 and `signerCount() - 1`)
     */
    function signerAt(uint256 index) external view virtual onlyProxy onlyInitialized returns (address) {
        return _signers.at(index);
    }

    /**
     * @dev Gets the full list of signer addresses authorized to sign on behalf of the contract.
     */
    function getSigners() external view virtual onlyProxy onlyInitialized returns (address[] memory) {
        return _signers.values();
    }

    ////////////////////////////////////////////////////////////
    //                      Owner Functions                   //
    ////////////////////////////////////////////////////////////

    /**
     * @dev Adds a signer to the authorized set. Only callable by the owner.
     */
    function addSigner(address signer) external virtual onlyOwner onlyProxy onlyInitialized {
        if (signer == address(0)) revert ZeroAddress();
        if (!_signers.add(signer)) revert SignerAlreadyAuthorized(signer);
        emit SignerAdded(signer);
    }

    /**
     * @dev Removes a signer from the authorized set. Only callable by the owner.
     */
    function removeSigner(address signer) external virtual onlyOwner onlyProxy onlyInitialized {
        if (!_signers.remove(signer)) revert SignerNotAuthorized(signer);
        emit SignerRemoved(signer);
    }

    /**
     * @dev Overrides `Ownable2StepUpgradeable.renounceOwnership` to disable renouncing ownership.
     *
     */
    function renounceOwnership() public view override onlyOwner {
        revert RenounceOwnershipDisabled();
    }

    /**
     * @notice Is called when upgrading the contract to check whether it should be performed.
     * @param newImplementation The address of the implementation being upgraded to.
     * @custom:reverts string If not called by the proxy owner.
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
