// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IAddressBook} from "./interfaces/IAddressBook.sol";
import {IWorldIDVerifier} from "./interfaces/IWorldIDVerifier.sol";
import {DateTimeLib} from "./libraries/DateTimeLib.sol";
import {ByteHasher} from "./libraries/ByteHasher.sol";

// @inheritdoc IAddressBook
contract AddressBook is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IAddressBook {
    using ByteHasher for bytes;

    ////////////////////////////////////////////////////////////
    //                        MEMBERS                         //
    ////////////////////////////////////////////////////////////

    // DO NOT REORDER! To ensure compatibility between upgrades, it is exceedingly important
    // that no reordering of these variables takes place.

    /// @dev World ID verifier used by register() to validate proofs.
    IWorldIDVerifier internal _worldIDVerifier;

    /// @dev First second of the UTC calendar month used as period 0 start.
    uint64 internal _periodStartTimestamp;

    /// @dev period => account => registered.
    mapping(uint32 => mapping(address => bool)) internal _periodAddressRegistered;

    /// @dev period => nullifier => used.
    mapping(uint32 => mapping(uint256 => bool)) internal _periodNullifierUsed;

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
     * @param periodStartTimestamp First second of UTC month used for period 0.
     */
    function initialize(address worldIDVerifier, uint64 rpId, uint64 issuerSchemaId, uint64 periodStartTimestamp)
        public
        virtual
        initializer
    {
        if (worldIDVerifier == address(0)) revert ZeroAddress();
        if (rpId == 0) revert InvalidRpId();
        if (issuerSchemaId == 0) revert InvalidIssuerSchemaId();
        if (!DateTimeLib.isUtcMonthStart(periodStartTimestamp)) {
            revert InvalidPeriodStartTimestamp(periodStartTimestamp);
        }

        __Ownable_init(msg.sender);
        __Ownable2Step_init();

        _worldIDVerifier = IWorldIDVerifier(worldIDVerifier);
        _rpId = rpId;
        _issuerSchemaId = issuerSchemaId;
        _periodStartTimestamp = periodStartTimestamp;
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

        uint32 currentPeriod = _getCurrentPeriod();
        if (currentPeriod == type(uint32).max) revert PeriodOutOfRange();

        _register(account, currentPeriod + 1, proof);
    }

    /// @inheritdoc IAddressBook
    function verify(address account) external view virtual onlyProxy onlyInitialized returns (bool) {
        return _periodAddressRegistered[_getCurrentPeriod()][account];
    }

    /// @inheritdoc IAddressBook
    function isRegisteredForPeriod(uint32 period, address account)
        external
        view
        virtual
        onlyProxy
        onlyInitialized
        returns (bool)
    {
        return _periodAddressRegistered[period][account];
    }

    /// @inheritdoc IAddressBook
    function getCurrentPeriod() external view virtual onlyProxy onlyInitialized returns (uint32) {
        return _getCurrentPeriod();
    }

    /// @inheritdoc IAddressBook
    function getActionForPeriod(uint32 period) external view virtual onlyProxy onlyInitialized returns (uint256) {
        return _getActionForPeriod(period);
    }

    /// @inheritdoc IAddressBook
    function getCurrentAction() external view virtual onlyProxy onlyInitialized returns (uint256) {
        return _getActionForPeriod(_getCurrentPeriod());
    }

    /// @inheritdoc IAddressBook
    function getWorldIDVerifier() external view virtual onlyProxy onlyInitialized returns (address) {
        return address(_worldIDVerifier);
    }

    /// @inheritdoc IAddressBook
    function getPeriodStartTimestamp() external view virtual onlyProxy onlyInitialized returns (uint64) {
        return _periodStartTimestamp;
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
    function _register(address account, uint32 targetPeriod, RegistrationProof calldata proof) internal virtual {
        uint256 periodEnd = DateTimeLib.periodEndTimestamp(_periodStartTimestamp, targetPeriod);
        if (uint256(proof.expiresAtMin) < periodEnd) {
            revert ExpirationBeforePeriodEnd(proof.expiresAtMin, periodEnd);
        }

        if (_periodNullifierUsed[targetPeriod][proof.nullifier]) {
            revert NullifierAlreadyUsed(proof.nullifier, targetPeriod);
        }

        if (_periodAddressRegistered[targetPeriod][account]) {
            revert AddressAlreadyRegistered(account, targetPeriod);
        }

        uint256 action = _getActionForPeriod(targetPeriod);
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

        _periodNullifierUsed[targetPeriod][proof.nullifier] = true;
        _periodAddressRegistered[targetPeriod][account] = true;

        emit AddressRegistered(targetPeriod, account);
    }

    /**
     * @notice Returns the current period index based on UTC calendar months.
     * @dev Period `0` starts at `_periodStartTimestamp`; each period is one UTC month.
     * @return The current period index.
     */
    function _getCurrentPeriod() internal view virtual returns (uint32) {
        if (block.timestamp < _periodStartTimestamp) revert PeriodNotStarted();

        (uint256 baseYear, uint256 baseMonth) = DateTimeLib.timestampToYearMonth(_periodStartTimestamp);
        (uint256 currentYear, uint256 currentMonth) = DateTimeLib.timestampToYearMonth(block.timestamp);

        uint256 period = DateTimeLib.monthIndex(currentYear, currentMonth) - DateTimeLib.monthIndex(baseYear, baseMonth);
        if (period > type(uint32).max) revert PeriodOutOfRange();

        return uint32(period);
    }

    /**
     * @notice Computes the action for a period as a field element.
     * @dev Uses a domain-separated keccak256 hash reduced via `>> 8` to fit the field.
     */
    function _getActionForPeriod(uint32 period) internal view virtual returns (uint256) {
        return abi.encodePacked(address(this), period).hashToField();
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

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal virtual override onlyProxy onlyOwner {}
}
