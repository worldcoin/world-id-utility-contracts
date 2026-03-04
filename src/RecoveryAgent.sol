// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract RecoveryAgent is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IERC1271 {
    using EnumerableSet for EnumerableSet.AddressSet;
    ////////////////////////////////////////////////////////////
    //                         Events                         //
    ////////////////////////////////////////////////////////////

    /// @notice Emitted when a signer is authorized (usually added).
    event SignerAuthorized(address indexed signer);

    /// @notice Emitted when a signer is not authorized (usually a revocation).
    event SignerUnauthorized(address indexed signer);

    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    /// @dev Thrown when a function is called on an uninitialized implementation.
    error ImplementationNotInitialized();

    /// @dev Thrown when attempting to set an address parameter to the zero address.
    error ZeroAddress();

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
    function _onlyInitialized() internal view {
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
    EnumerableSet.AddressSet private _signers;

    uint256[49] private __gap;

    ////////////////////////////////////////////////////////////
    //                       Constructor                      //
    ////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender); // `OwnableUpgradeable` delegation
        __Ownable2Step_init();
    }

    ////////////////////////////////////////////////////////////
    //                  Public View Functions                 //
    ////////////////////////////////////////////////////////////

    /**
     * @dev Returns whether the signature is authorized for a given hash.
     * @param hash Hash of the data to be signed
     * @param signature Signature byte array associated with `hash`
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
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        if (err == ECDSA.RecoverError.NoError && _signers.contains(signer)) {
            return _MAGICVALUE;
        } else {
            return 0xffffffff;
        }
    }

    function isAuthorizedSigner(address signer) external view onlyProxy onlyInitialized returns (bool) {
        return _signers.contains(signer);
    }

    function signerCount() external view onlyProxy onlyInitialized returns (uint256) {
        return _signers.length();
    }

    function signerAt(uint256 index) external view onlyProxy onlyInitialized returns (address) {
        return _signers.at(index);
    }

    function getSigners() external view onlyProxy onlyInitialized returns (address[] memory) {
        return _signers.values();
    }

    ////////////////////////////////////////////////////////////
    //                      Owner Functions                   //
    ////////////////////////////////////////////////////////////

    function updateSigner(address signer, bool isAuthorized) external onlyOwner onlyProxy onlyInitialized {
        if (signer == address(0)) {
            revert ZeroAddress();
        }

        if (isAuthorized) {
            _signers.add(signer);
            emit SignerAuthorized(signer);
        } else {
            _signers.remove(signer);
            emit SignerUnauthorized(signer);
        }
    }

    /// @notice Is called when upgrading the contract to check whether it should be performed.
    /// @param newImplementation The address of the implementation being upgraded to.
    /// @custom:reverts string If not called by the proxy owner.
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
