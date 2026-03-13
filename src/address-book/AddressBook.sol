// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IAddressBook} from "./interfaces/IAddressBook.sol";
import {IWorldIDVerifier} from "./interfaces/IWorldIDVerifier.sol";
import {ByteHasher} from "./libraries/ByteHasher.sol";

contract AddressBook is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IAddressBook {
    using ByteHasher for bytes;

    ////////////////////////////////////////////////////////////
    //                        MEMBERS                         //
    ////////////////////////////////////////////////////////////

    // DO NOT REORDER! To ensure compatibility between upgrades, it is exceedingly important
    // that no reordering of these variables takes place.

    /// @dev World ID verifier used by register() to validate proofs.
    IWorldIDVerifier internal _worldIDVerifier;

    /// @dev Epoch duration in seconds used to derive the current period.
    uint64 internal _epochDuration;

    /// @dev action => account => registered.
    mapping(uint256 => mapping(address => bool)) internal _actionAddressRegistered;

    /// @dev action => nullifier => used.
    mapping(uint256 => mapping(uint256 => bool)) internal _actionNullifierUsed;

    /// @dev RP id used for all verifier calls made by this address book.
    uint64 internal _rpId;

    /// @dev The expected issuer schema id for the proofs
    uint64 internal _issuerSchemaId;

    ////////////////////////////////////////////////////////////
    //                        Modifiers                       //
    ////////////////////////////////////////////////////////////

    /// @notice Ensures the implementation has been initialized via proxy.
    modifier onlyInitialized() {
        _onlyInitialized();
        _;
    }

    /// @dev Reverts if this implementation has not been initialized.
    function _onlyInitialized() internal view {
        if (_getInitializedVersion() == 0) {
            revert ImplementationNotInitialized();
        }
    }

    ////////////////////////////////////////////////////////////
    //                      CONSTRUCTOR                       //
    ////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    ////////////////////////////////////////////////////////////
    //                      INITIALIZER                       //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Initializes the AddressBook contract.
     * @param worldIDVerifier Address of WorldIDVerifier.
     * @param rpId Relying-party identifier bound to this address book.
     * @param issuerSchemaId The expected issuer schema id for proof verification.
     * @param epochDuration Duration of each period in seconds.
     */
    function initialize(address worldIDVerifier, uint64 rpId, uint64 issuerSchemaId, uint64 epochDuration)
        public
        virtual
        initializer
    {
        if (worldIDVerifier == address(0)) revert ZeroAddress();
        if (rpId == 0) revert InvalidRpId();
        if (issuerSchemaId == 0) revert InvalidIssuerSchemaId();
        if (epochDuration == 0) revert InvalidEpochDuration();

        __Ownable_init(msg.sender);
        __Ownable2Step_init();

        _worldIDVerifier = IWorldIDVerifier(worldIDVerifier);
        _rpId = rpId;
        _issuerSchemaId = issuerSchemaId;
        _epochDuration = epochDuration;
    }

    ////////////////////////////////////////////////////////////
    //                   EXTERNAL FUNCTIONS                   //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IAddressBook
    function register(address account, RegistrationProof calldata proof) external virtual onlyProxy onlyInitialized {
        if (account == address(0)) revert InvalidAccount();
        _register(account, _getCurrentPeriod(), proof);
    }

    /// @inheritdoc IAddressBook
    function registerNextPeriod(address account, RegistrationProof calldata proof)
        external
        virtual
        onlyProxy
        onlyInitialized
    {
        if (account == address(0)) revert InvalidAccount();

        uint64 currentPeriod = _getCurrentPeriod();
        if (currentPeriod == type(uint64).max) revert PeriodOutOfRange();

        _register(account, currentPeriod + 1, proof);
    }

    /// @inheritdoc IAddressBook
    function isVerified(address account) external view virtual onlyProxy onlyInitialized returns (bool) {
        return _actionAddressRegistered[_getCurrentAction()][account];
    }

    /// @inheritdoc IAddressBook
    function isRegisteredForAction(uint256 action, address account)
        external
        view
        virtual
        onlyProxy
        onlyInitialized
        returns (bool)
    {
        return _actionAddressRegistered[action][account];
    }

    /// @inheritdoc IAddressBook
    function getCurrentPeriod() external view virtual onlyProxy onlyInitialized returns (uint64) {
        return _getCurrentPeriod();
    }

    /// @inheritdoc IAddressBook
    function getActionForPeriod(uint64 period) external view virtual onlyProxy onlyInitialized returns (uint256) {
        return _getActionForPeriod(period);
    }

    /// @inheritdoc IAddressBook
    function getCurrentAction() external view virtual onlyProxy onlyInitialized returns (uint256) {
        return _getCurrentAction();
    }

    /// @inheritdoc IAddressBook
    function getWorldIDVerifier() external view virtual onlyProxy onlyInitialized returns (address) {
        return address(_worldIDVerifier);
    }

    /// @inheritdoc IAddressBook
    function getEpochDuration() external view virtual onlyProxy onlyInitialized returns (uint64) {
        return _epochDuration;
    }

    /// @inheritdoc IAddressBook
    function getRpId() external view virtual onlyProxy onlyInitialized returns (uint64) {
        return _rpId;
    }

    /// @inheritdoc IAddressBook
    function getIssuerSchemaId() external view virtual onlyProxy onlyInitialized returns (uint64) {
        return _issuerSchemaId;
    }

    ////////////////////////////////////////////////////////////
    //                   INTERNAL FUNCTIONS                   //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Registers an account for a period after proof verification.
     * @param account The account to mark as registered.
     * @param targetPeriod The target period index for registration.
     * @param proof The World ID proof payload to verify.
     */
    function _register(address account, uint64 targetPeriod, RegistrationProof calldata proof) internal virtual {
        uint256 action = _getActionForPeriod(targetPeriod);

        if (_actionNullifierUsed[action][proof.nullifier]) {
            revert NullifierAlreadyUsed(proof.nullifier, action);
        }

        if (_actionAddressRegistered[action][account]) {
            revert AddressAlreadyRegistered(account, action);
        }

        uint256 periodEnd = _getPeriodEndTimestamp(targetPeriod);
        if (uint256(proof.expiresAtMin) < periodEnd) {
            revert ExpirationBeforePeriodEnd(proof.expiresAtMin, periodEnd);
        }

        uint256 signalHash = _computeSignalHash(account);

        _worldIDVerifier.verify(
            proof.nullifier,
            action,
            _rpId,
            proof.nonce,
            signalHash,
            proof.expiresAtMin,
            _issuerSchemaId,
            0, // Explicitly this contract does not enforce this constraint
            proof.zeroKnowledgeProof
        );

        _actionNullifierUsed[action][proof.nullifier] = true;
        _actionAddressRegistered[action][account] = true;

        emit AddressRegistered(targetPeriod, _epochDuration, account);
    }

    /**
     * @notice Returns the current period index based on fixed-duration epochs.
     * @return The current period index.
     */
    function _getCurrentPeriod() internal view virtual returns (uint64) {
        uint256 period = block.timestamp / _epochDuration;
        if (period > type(uint64).max) revert PeriodOutOfRange();

        return uint64(period);
    }

    /**
     * @notice Returns the exclusive end timestamp of a target period.
     * @param period The target period index.
     * @return The period end boundary in seconds since the Unix epoch.
     */
    function _getPeriodEndTimestamp(uint64 period) internal view virtual returns (uint256) {
        return (uint256(period) + 1) * _epochDuration;
    }

    /**
     * @notice Computes the action for a period as a field element.
     * @dev Hashes `abi.encodePacked(uint256(period), _epochDuration)` and reduces via `>> 8` to fit the field.
     */
    function _getActionForPeriod(uint64 period) internal view virtual returns (uint256) {
        return abi.encodePacked(uint256(period), _epochDuration).hashToField();
    }

    /**
     * @notice Computes the action for the current period as a field element.
     * @return The current action.
     */
    function _getCurrentAction() internal view virtual returns (uint256) {
        return _getActionForPeriod(_getCurrentPeriod());
    }

    /**
     * @notice Computes the expected signal for an account being verified.
     * @param account The account address being verified
     * @return The signal hash (field element) expected by the verifier.
     */
    function _computeSignalHash(address account) internal pure virtual returns (uint256) {
        return abi.encodePacked(account).hashToField();
    }

    ////////////////////////////////////////////////////////////
    //                    OWNER FUNCTIONS                     //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IAddressBook
    function updateWorldIDVerifier(address newWorldIDVerifier) external virtual onlyOwner onlyProxy onlyInitialized {
        if (newWorldIDVerifier == address(0)) revert ZeroAddress();

        address oldWorldIDVerifier = address(_worldIDVerifier);
        _worldIDVerifier = IWorldIDVerifier(newWorldIDVerifier);

        emit WorldIDVerifierUpdated(oldWorldIDVerifier, newWorldIDVerifier);
    }

    /// @inheritdoc IAddressBook
    function updateIssuerSchemaId(uint64 newIssuerSchemaId) external virtual onlyOwner onlyProxy onlyInitialized {
        if (newIssuerSchemaId == 0) revert InvalidIssuerSchemaId();

        uint64 oldIssuerSchemaId = _issuerSchemaId;
        _issuerSchemaId = newIssuerSchemaId;

        emit IssuerSchemaIdUpdated(oldIssuerSchemaId, newIssuerSchemaId);
    }

    /// @inheritdoc IAddressBook
    function updateEpochDuration(uint64 newEpochDuration) external virtual onlyOwner onlyProxy onlyInitialized {
        if (newEpochDuration == 0) revert InvalidEpochDuration();

        uint64 oldEpochDuration = _epochDuration;
        _epochDuration = newEpochDuration;

        emit EpochDurationUpdated(oldEpochDuration, newEpochDuration);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal virtual override onlyProxy onlyOwner {}
}
