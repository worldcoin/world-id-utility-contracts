// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {IAddressBook} from "./interfaces/IAddressBook.sol";
import {IWorldIDVerifier} from "./interfaces/IWorldIDVerifier.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title AddressBook
 * @author World Contributors
 * @notice Action-scoped soft-cache for World ID proof verifications.
 * @dev Designed for proxy deployments (UUPS).
 */
contract AddressBook is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, EIP712Upgradeable, IAddressBook {
    ////////////////////////////////////////////////////////////
    //                         ERRORS                         //
    ////////////////////////////////////////////////////////////

    /// @notice Thrown when a function is called before initialization.
    error ImplementationNotInitialized();

    /// @notice Thrown when attempting to set an address parameter to zero.
    error ZeroAddress();

    ////////////////////////////////////////////////////////////
    //                        MEMBERS                         //
    ////////////////////////////////////////////////////////////

    // DO NOT REORDER! To ensure compatibility between upgrades, it is exceedingly important
    // that no reordering of these variables takes place.

    /// @dev World ID verifier used by register() to validate proofs.
    IWorldIDVerifier internal _worldIDVerifier;

    /// @dev First second of the UTC calendar month used as period 0 start.
    uint64 internal _periodStartTimestamp;

    /// @dev If true, registration is limited to current or next period only.
    bool internal _enforceCurrentOrNextPeriod;

    /// @dev epochId => account => registered.
    mapping(bytes32 => mapping(address => bool)) internal _epochAddressRegistered;

    /// @dev epochId => nullifier => used.
    mapping(bytes32 => mapping(uint256 => bool)) internal _epochNullifierUsed;

    ////////////////////////////////////////////////////////////
    //                       CONSTANTS                        //
    ////////////////////////////////////////////////////////////

    string public constant EIP712_NAME = "AddressBook";
    string public constant EIP712_VERSION = "1.0";
    uint256 internal constant SECONDS_PER_DAY = 24 * 60 * 60;
    int256 internal constant OFFSET19700101 = 2440588;

    ////////////////////////////////////////////////////////////
    //                        MODIFIERS                       //
    ////////////////////////////////////////////////////////////

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
     * @param periodStartTimestamp First second of UTC month used for period 0.
     * @param enforceCurrentOrNextPeriod Whether to restrict registration to current/next period.
     */
    function initialize(
        address worldIDVerifier,
        uint64 periodStartTimestamp,
        bool enforceCurrentOrNextPeriod
    ) public virtual initializer {
        if (worldIDVerifier == address(0)) revert ZeroAddress();
        if (!_isUtcMonthStart(periodStartTimestamp)) revert InvalidPeriodStartTimestamp(periodStartTimestamp);

        __Ownable_init(msg.sender);
        __Ownable2Step_init();
        __EIP712_init(EIP712_NAME, EIP712_VERSION);

        _worldIDVerifier = IWorldIDVerifier(worldIDVerifier);
        _periodStartTimestamp = periodStartTimestamp;
        _enforceCurrentOrNextPeriod = enforceCurrentOrNextPeriod;
    }

    ////////////////////////////////////////////////////////////
    //                   EXTERNAL FUNCTIONS                   //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IAddressBook
    function register(address account, uint32 targetPeriod, EpochData calldata epoch, RegistrationProof calldata proof)
        external
        virtual
        onlyProxy
        onlyInitialized
    {
        if (account == address(0)) revert InvalidAccount();
        _register(account, targetPeriod, epoch, proof);
    }

    /// @inheritdoc IAddressBook
    function verify(EpochData calldata epoch, address account)
        external
        view
        virtual
        onlyProxy
        onlyInitialized
        returns (bool)
    {
        uint32 currentPeriod = _getCurrentPeriod();
        bytes32 epochId = _computeEpochId(currentPeriod, epoch.action);
        return _epochAddressRegistered[epochId][account];
    }

    /// @inheritdoc IAddressBook
    function isRegisteredForPeriod(uint32 period, EpochData calldata epoch, address account)
        external
        view
        virtual
        onlyProxy
        onlyInitialized
        returns (bool)
    {
        bytes32 epochId = _computeEpochId(period, epoch.action);
        return _epochAddressRegistered[epochId][account];
    }

    /// @inheritdoc IAddressBook
    function getCurrentPeriod() external view virtual onlyProxy onlyInitialized returns (uint32) {
        return _getCurrentPeriod();
    }

    /// @inheritdoc IAddressBook
    function computeEpochId(uint32 period, EpochData calldata epoch) external pure virtual returns (bytes32) {
        return _computeEpochId(period, epoch.action);
    }

    /// @inheritdoc IAddressBook
    function computeSignal(uint32, EpochData calldata, address account)
        external
        view
        virtual
        onlyProxy
        onlyInitialized
        returns (string memory)
    {
        return _computeSignal(account);
    }

    /// @inheritdoc IAddressBook
    function computeSignalHash(uint32, EpochData calldata, address account)
        external
        view
        virtual
        onlyProxy
        onlyInitialized
        returns (uint256)
    {
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
    function getEnforceCurrentOrNextPeriod() external view virtual onlyProxy onlyInitialized returns (bool) {
        return _enforceCurrentOrNextPeriod;
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
    function setEnforceCurrentOrNextPeriod(bool enabled) external virtual onlyOwner onlyProxy onlyInitialized {
        bool oldValue = _enforceCurrentOrNextPeriod;
        _enforceCurrentOrNextPeriod = enabled;

        emit EnforceCurrentOrNextPeriodUpdated(oldValue, enabled);
    }

    ////////////////////////////////////////////////////////////
    //                   INTERNAL FUNCTIONS                   //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Registers an account for a period+action epoch after proof verification.
     * @param account The account to mark as registered.
     * @param targetPeriod The target period index for registration.
     * @param epoch The action-scoped epoch data.
     * @param proof The World ID proof payload to verify.
     */
    function _register(address account, uint32 targetPeriod, EpochData calldata epoch, RegistrationProof calldata proof)
        internal
        virtual
    {
        uint32 currentPeriod = _getCurrentPeriod();

        if (_enforceCurrentOrNextPeriod) {
            // Compare "next period" in uint256 space to avoid uint32 overflow when currentPeriod == type(uint32).max.
            bool isCurrentPeriod = targetPeriod == currentPeriod;
            bool isNextPeriod = uint256(targetPeriod) == uint256(currentPeriod) + 1;
            if (!isCurrentPeriod && !isNextPeriod) {
                revert InvalidTargetPeriod(targetPeriod, currentPeriod);
            }
        }

        uint256 epochPeriodEnd = _periodEndTimestamp(targetPeriod);
        if (uint256(proof.expiresAtMin) < epochPeriodEnd) {
            revert ExpirationBeforeEpochEnd(proof.expiresAtMin, epochPeriodEnd);
        }

        bytes32 epochId = _computeEpochId(targetPeriod, epoch.action);

        if (_epochNullifierUsed[epochId][proof.nullifier]) {
            revert NullifierAlreadyUsed(proof.nullifier, epochId);
        }

        if (_epochAddressRegistered[epochId][account]) {
            revert AddressAlreadyRegistered(account, epochId);
        }

        uint256 signalHash = _computeSignalHash(account);

        _worldIDVerifier.verify(
            proof.nullifier,
            epoch.action,
            proof.rpId,
            proof.nonce,
            signalHash,
            proof.expiresAtMin,
            proof.issuerSchemaId,
            proof.credentialGenesisIssuedAtMin,
            proof.zeroKnowledgeProof
        );

        _epochNullifierUsed[epochId][proof.nullifier] = true;
        _epochAddressRegistered[epochId][account] = true;

        emit AddressRegistered(epochId, targetPeriod, epoch.action, account, proof.nullifier);
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

        (uint256 baseYear, uint256 baseMonth) = _timestampToYearMonth(_periodStartTimestamp);
        (uint256 currentYear, uint256 currentMonth) = _timestampToYearMonth(block.timestamp);

        uint256 period = _monthIndex(currentYear, currentMonth) - _monthIndex(baseYear, baseMonth);
        if (period > type(uint32).max) revert PeriodOutOfRange();

        return uint32(period);
    }

    /**
     * @notice Computes the storage key for a period+action epoch.
     * @param period The period index.
     * @param action The World ID action value.
     * @return The epoch identifier used in storage mappings.
     */
    function _computeEpochId(uint32 period, uint256 action) internal pure virtual returns (bytes32) {
        return keccak256(abi.encode(period, action));
    }

    /**
     * @notice Computes the canonical signal hash bound to an account.
     * @dev Hashes UTF-8 bytes of the canonical signal string and right-shifts by 8 bits.
     * @param account The account used to derive the signal.
     * @return The signal hash expected by the verifier.
     */
    function _computeSignalHash(address account) internal pure virtual returns (uint256) {
        // Match the authenticator pipeline, which hashes UTF-8 signal bytes.
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

    /**
     * @notice Returns the exclusive end timestamp of the given target period.
     * @dev End timestamp is the first second of the following UTC month.
     * @param period The target period index.
     * @return The UTC timestamp for the period end boundary.
     */
    function _periodEndTimestamp(uint32 period) internal view returns (uint256) {
        (uint256 baseYear, uint256 baseMonth) = _timestampToYearMonth(_periodStartTimestamp);
        uint256 nextMonthIndex = _monthIndex(baseYear, baseMonth) + uint256(period) + 1;
        (uint256 endYear, uint256 endMonth) = _indexToYearMonth(nextMonthIndex);
        return _daysFromDate(endYear, endMonth, 1) * SECONDS_PER_DAY;
    }

    /**
     * @notice Checks whether a timestamp is exactly at a UTC month boundary.
     * @param timestamp The timestamp to validate.
     * @return True if `timestamp` is `YYYY-MM-01 00:00:00 UTC`.
     */
    function _isUtcMonthStart(uint256 timestamp) internal pure returns (bool) {
        if (timestamp % SECONDS_PER_DAY != 0) return false;

        (, , uint256 day) = _daysToDate(timestamp / SECONDS_PER_DAY);
        return day == 1;
    }

    /**
     * @notice Converts a Unix timestamp to UTC year and month components.
     * @param timestamp The Unix timestamp in seconds.
     * @return year The UTC year.
     * @return month The UTC month in range [1..12].
     */
    function _timestampToYearMonth(uint256 timestamp) internal pure returns (uint256 year, uint256 month) {
        (year, month,) = _daysToDate(timestamp / SECONDS_PER_DAY);
    }

    /**
     * @notice Converts year-month to a monotonic month index.
     * @param year The UTC year.
     * @param month The UTC month in range [1..12].
     * @return The zero-based month index used for period arithmetic.
     */
    function _monthIndex(uint256 year, uint256 month) internal pure returns (uint256) {
        return year * 12 + (month - 1);
    }

    /**
     * @notice Converts a monotonic month index back to year-month components.
     * @param index The zero-based month index.
     * @return year The UTC year.
     * @return month The UTC month in range [1..12].
     */
    function _indexToYearMonth(uint256 index) internal pure returns (uint256 year, uint256 month) {
        year = index / 12;
        month = (index % 12) + 1;
    }

    /**
     * @notice Converts a UTC date to days since Unix epoch.
     * @dev Uses the Julian day conversion algorithm.
     * @param year The UTC year.
     * @param month The UTC month in range [1..12].
     * @param day The UTC day in range [1..31].
     * @return _days Number of days since 1970-01-01 UTC.
     */
    function _daysFromDate(uint256 year, uint256 month, uint256 day) internal pure returns (uint256 _days) {
        int256 _year = int256(year);
        int256 _month = int256(month);
        int256 _day = int256(day);

        int256 __days = _day - 32075 + 1461 * (_year + 4800 + (_month - 14) / 12) / 4
            + 367 * (_month - 2 - ((_month - 14) / 12) * 12) / 12 - 3 * ((_year + 4900 + (_month - 14) / 12) / 100) / 4
            - OFFSET19700101;

        _days = uint256(__days);
    }

    /**
     * @notice Converts days since Unix epoch into a UTC date.
     * @dev Uses the Julian day conversion algorithm.
     * @param _days Number of days since 1970-01-01 UTC.
     * @return year The UTC year.
     * @return month The UTC month in range [1..12].
     * @return day The UTC day in range [1..31].
     */
    function _daysToDate(uint256 _days) internal pure returns (uint256 year, uint256 month, uint256 day) {
        int256 __days = int256(_days);

        int256 L = __days + 68569 + OFFSET19700101;
        int256 N = 4 * L / 146097;
        L = L - (146097 * N + 3) / 4;
        int256 _year = 4000 * (L + 1) / 1461001;
        L = L - 1461 * _year / 4 + 31;
        int256 _month = 80 * L / 2447;
        int256 _day = L - 2447 * _month / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint256(_year);
        month = uint256(_month);
        day = uint256(_day);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal virtual override onlyProxy onlyOwner {}
}
