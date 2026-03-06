// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IAddressBook} from "./interfaces/IAddressBook.sol";
import {IWorldIDVerifier} from "./interfaces/IWorldIDVerifier.sol";
import {DateTimeLib} from "./libraries/DateTimeLib.sol";

/**
 * @title AddressBook
 * @author World Contributors
 * @notice Period-scoped soft-cache for World ID proof verifications, acting as its own RP.
 * @dev Designed for proxy deployments (UUPS).
 */
contract AddressBook is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IAddressBook {
    ////////////////////////////////////////////////////////////
    //                         ERRORS                         //
    ////////////////////////////////////////////////////////////

    /// @notice Thrown when a function is called before initialization.
    error ImplementationNotInitialized();

    /// @notice Thrown when attempting to set an address parameter to zero.
    error ZeroAddress();

    ////////////////////////////////////////////////////////////
    //                        CONSTANTS                       //
    ////////////////////////////////////////////////////////////

    string internal constant ACTION_DOMAIN_SEPARATOR = "WORLD_ID_ADDRESS_BOOK_ACTION";

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

    /// @notice Ensures the implementation has been initialized via proxy.
    modifier onlyInitialized() {
        _onlyInitialized();
        _;
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
    function initialize(address worldIDVerifier, uint64 rpId, uint64 periodStartTimestamp) public virtual initializer {
        if (worldIDVerifier == address(0)) revert ZeroAddress();
        if (rpId == 0) revert InvalidRpId();
        if (!DateTimeLib.isUtcMonthStart(periodStartTimestamp)) {
            revert InvalidPeriodStartTimestamp(periodStartTimestamp);
        }

        __Ownable_init(msg.sender);
        __Ownable2Step_init();

        _worldIDVerifier = IWorldIDVerifier(worldIDVerifier);
        _rpId = rpId;
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
    function computeSignal(address account) external view virtual onlyProxy onlyInitialized returns (string memory) {
        return _computeSignal(account);
    }

    /// @inheritdoc IAddressBook
    function computeSignalHash(address account) external view virtual onlyProxy onlyInitialized returns (uint256) {
        return _computeSignalHash(account);
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
            proof.issuerSchemaId,
            proof.credentialGenesisIssuedAtMin,
            proof.zeroKnowledgeProof
        );

        _periodNullifierUsed[targetPeriod][proof.nullifier] = true;
        _periodAddressRegistered[targetPeriod][account] = true;

        emit AddressRegistered(targetPeriod, account, action, proof.nullifier);
    }

    /// @dev Reverts if this implementation has not been initialized.
    function _onlyInitialized() internal view {
        if (_getInitializedVersion() == 0) {
            revert ImplementationNotInitialized();
        }
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
        return uint256(keccak256(abi.encodePacked(ACTION_DOMAIN_SEPARATOR, address(this), period))) >> 8;
    }

    /**
     * @notice Computes the canonical signal hash bound to an account.
     * @dev Hashes UTF-8 bytes of the canonical signal string and right-shifts by 8 bits.
     * @param account The account used to derive the signal.
     * @return The signal hash expected by the verifier.
     */
    function _computeSignalHash(address account) internal pure virtual returns (uint256) {
        string memory signal = _computeSignal(account);
        return uint256(keccak256(bytes(signal))) >> 8;
    }

    /**
     * @notice Computes the canonical signal string for an account.
     * @param account The account to encode.
     * @return The lowercase 0x-prefixed 20-byte hex address string.
     */
    function _computeSignal(address account) internal pure virtual returns (string memory) {
        return Strings.toHexString(uint256(uint160(account)), 20);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal virtual override onlyProxy onlyOwner {}
}
