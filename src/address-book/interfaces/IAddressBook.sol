// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IAddressBook
 * @author World Contributors
 * @notice Soft-cache contract for action-scoped World ID verification results.
 */
interface IAddressBook {
    ////////////////////////////////////////////////////////////
    //                        STRUCTS                         //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Logical verification context.
     * @param action RP-defined action field value used by World ID proofs.
     */
    struct EpochData {
        uint256 action;
    }

    /**
     * @notice World ID proof payload needed for registration.
     */
    struct RegistrationProof {
        uint256 nullifier;
        uint64 rpId;
        uint256 nonce;
        uint64 expiresAtMin;
        uint64 issuerSchemaId;
        uint256 credentialGenesisIssuedAtMin;
        uint256[5] zeroKnowledgeProof;
    }

    ////////////////////////////////////////////////////////////
    //                        ERRORS                          //
    ////////////////////////////////////////////////////////////

    /// @notice Thrown when `periodLengthSeconds` is set to zero.
    error InvalidPeriodLength();

    /// @notice Thrown when registration/verification is attempted before period 0 start.
    error PeriodNotStarted();

    /// @notice Thrown when computed period does not fit into `uint32`.
    error PeriodOutOfRange();

    /// @notice Thrown when `register` is called with the zero address as `account`.
    error InvalidAccount();

    /// @notice Thrown when `targetPeriod` is not allowed by current registration policy.
    /// @param targetPeriod The user-provided target period.
    /// @param currentPeriod The current active period at call time.
    error InvalidTargetPeriod(uint32 targetPeriod, uint32 currentPeriod);

    /// @notice Thrown when proof expiry does not cover the full target period.
    /// @param expiresAtMin The expiry bound carried in the proof.
    /// @param epochPeriodEnd The required minimum expiry for the target period end.
    error ExpirationBeforeEpochEnd(uint64 expiresAtMin, uint256 epochPeriodEnd);

    /// @notice Thrown when a nullifier was already consumed for the same epoch key.
    /// @param nullifier The duplicate nullifier.
    /// @param epochId The epoch key where the nullifier was already used.
    error NullifierAlreadyUsed(uint256 nullifier, bytes32 epochId);

    /// @notice Thrown when an address is already registered for the same epoch key.
    /// @param account The duplicate account.
    /// @param epochId The epoch key where the account is already registered.
    error AddressAlreadyRegistered(address account, bytes32 epochId);

    ////////////////////////////////////////////////////////////
    //                        EVENTS                          //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Emitted when an address is registered for a period/action context.
     */
    event AddressRegistered(
        bytes32 indexed epochId, uint32 indexed period, uint256 action, address account, uint256 nullifier
    );

    /**
     * @notice Emitted when the WorldID verifier contract is updated.
     */
    event WorldIDVerifierUpdated(address oldWorldIDVerifier, address newWorldIDVerifier);

    /**
     * @notice Emitted when registration period guard is toggled.
     */
    event EnforceCurrentOrNextPeriodUpdated(bool oldValue, bool newValue);

    ////////////////////////////////////////////////////////////
    //                   EXTERNAL FUNCTIONS                   //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Registers an address for the given target period and context.
     * @dev Any caller may register any `account`.
     */
    function register(address account, uint32 targetPeriod, EpochData calldata epoch, RegistrationProof calldata proof)
        external;

    /**
     * @notice Returns whether `account` is registered in the currently active period for this context.
     */
    function verify(EpochData calldata epoch, address account) external view returns (bool);

    /**
     * @notice Raw lookup for an explicit period.
     */
    function isRegisteredForPeriod(uint32 period, EpochData calldata epoch, address account)
        external
        view
        returns (bool);

    /**
     * @notice Returns the currently active period index.
     */
    function getCurrentPeriod() external view returns (uint32);

    /**
     * @notice Computes the epoch key for the given context.
     */
    function computeEpochId(uint32 period, EpochData calldata epoch) external pure returns (bytes32);

    /**
     * @notice Computes the canonical signal string for `account`.
     */
    function computeSignal(uint32 period, EpochData calldata epoch, address account)
        external
        view
        returns (string memory);

    /**
     * @notice Computes the signal hash bound to `account`.
     */
    function computeSignalHash(uint32 period, EpochData calldata epoch, address account) external view returns (uint256);

    /**
     * @notice Returns the WorldID verifier address.
     */
    function getWorldIDVerifier() external view returns (address);

    /**
     * @notice Returns the configured period start timestamp.
     */
    function getPeriodStartTimestamp() external view returns (uint64);

    /**
     * @notice Returns the configured period length in seconds.
     */
    function getPeriodLengthSeconds() external view returns (uint64);

    /**
     * @notice Returns whether registration is limited to current or next period.
     */
    function getEnforceCurrentOrNextPeriod() external view returns (bool);

    ////////////////////////////////////////////////////////////
    //                     OWNER FUNCTIONS                    //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Updates the WorldID verifier address.
     */
    function updateWorldIDVerifier(address newWorldIDVerifier) external;

    /**
     * @notice Toggles whether registration is restricted to current/next period.
     */
    function setEnforceCurrentOrNextPeriod(bool enabled) external;
}
