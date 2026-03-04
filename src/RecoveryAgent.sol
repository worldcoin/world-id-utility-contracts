// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract RecoveryAgent is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IERC1271 {
    ////////////////////////////////////////////////////////////
    //                         Events                         //
    ////////////////////////////////////////////////////////////

    /// @notice Emitted when a signer is authorized (usually added).
    event SignerAuthorized(address indexed signer);

    /// @notice Emitted when a signer is not authorized (usually a revokation).
    event SignerUnauthorized(address indexed signer);

    ////////////////////////////////////////////////////////////
    //                         Errors                         //
    ////////////////////////////////////////////////////////////

    /// @notice Thrown when a function is called on an uninitialized implementation.
    error ImplementationNotInitialized();

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

    string public constant EIP712_NAME = "RecoveryAgent";
    string public constant EIP712_VERSION = "1.0";

    // @dev ERC-1271 magic value https://eips.ethereum.org/EIPS/eip-1271
    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 internal constant _MAGICVALUE = 0x1626ba7e;

    ////////////////////////////////////////////////////////////
    //                        Members                         //
    ////////////////////////////////////////////////////////////

    // DO NOT REORDER! To ensure compatibility between upgrades, it is exceedingly important
    // that no reordering of these variables takes place. If reordering happens, a storage
    // clash will occur (effectively a memory safety error).

    /// @dev The list of authorized signers that can sign on behalf of the contract. Using a mapping for O(1) lookups.
    mapping(address => bool) internal _isAuthorizedSigner;

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
        if (err == ECDSA.RecoverError.NoError && _isAuthorizedSigner[signer]) {
            return _MAGICVALUE;
        } else {
            return 0xffffffff;
        }
    }

    function isAuthorizedSigner(address signer) external view onlyProxy onlyInitialized returns (bool) {
        return _isAuthorizedSigner[signer];
    }

    ////////////////////////////////////////////////////////////
    //                      Owner Functions                   //
    ////////////////////////////////////////////////////////////

    function updateSigner(address signer, bool isAuthorized) external onlyOwner onlyProxy onlyInitialized {
        _isAuthorizedSigner[signer] = isAuthorized;
        if (isAuthorized) {
            emit SignerAuthorized(signer);
        } else {
            emit SignerUnauthorized(signer);
        }
    }

    /// @notice Is called when upgrading the contract to check whether it should be performed.
    /// @param newImplementation The address of the implementation being upgraded to.
    /// @custom:reverts string If not called by the proxy owner.
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
