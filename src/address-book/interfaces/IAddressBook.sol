// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title AddressBook
 * @author World Contributors
 * @notice Period-scoped soft-cache for World ID proof verifications, acting as its own RP.
 * @dev Designed for proxy deployments (UUPS).
 * @custom:repo https://github.com/worldcoin/world-id-utility-contracts
 * @custom:docs https://docs.world.org/mini-apps/reference/address-book
 */
interface IAddressBook {
    ////////////////////////////////////////////////////////////
    //                        STRUCTS                         //
    ////////////////////////////////////////////////////////////

    /**
     * @notice World ID proof payload needed for registration.
     * @dev Some proof attributes are explicitly expected by the contract.
     */
    struct RegistrationProof {
        uint256 nullifier;
        uint256 nonce;
        uint64 expiresAtMin;
        uint256[5] zeroKnowledgeProof;
    }

    ////////////////////////////////////////////////////////////
    //                        ERRORS                          //
    ////////////////////////////////////////////////////////////

    /// @notice Thrown when `epochDuration` is zero.
    error InvalidEpochDuration();

    /// @notice Thrown when a computed period boundary does not fit into `uint64`.
    error PeriodOutOfRange();

    /// @notice Thrown when `register` is called with the zero address as `account`.
    error InvalidAccount();

    /// @notice Thrown when proof expiry does not cover the full target period.
    /// @param expiresAtMin The expiry bound carried in the proof.
    /// @param periodEnd The required minimum expiry for the target period end.
    error ExpirationBeforePeriodEnd(uint64 expiresAtMin, uint64 periodEnd);

    /// @notice Thrown when an RP id of `0` is provided where a configured RP id is required.
    error InvalidRpId();

    /// @notice Thrown when the provided issuer schema id is not valid during initialization.
    error InvalidIssuerSchemaId();

    /// @notice Thrown when a nullifier was already consumed by this address book.
    /// @param nullifier The duplicate nullifier.
    /// @param action The action tied to the duplicate registration attempt.
    error NullifierAlreadyUsed(uint256 nullifier, uint256 action);

    /// @notice Thrown when an address is already registered for the same period.
    /// @param account The duplicate account.
    /// @param action The action where the account is already registered.
    error AddressAlreadyRegistered(address account, uint256 action);

    /// @notice Thrown when a function is called before initialization.
    error ImplementationNotInitialized();

    /// @notice Thrown when attempting to set an address parameter to zero.
    error ZeroAddress();

    ////////////////////////////////////////////////////////////
    //                        EVENTS                          //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Emitted when an address is registered for a period.
     */
    event AddressRegistered(uint64 indexed period, uint64 epochDuration, address indexed account);

    /**
     * @notice Emitted when the WorldID verifier contract is updated.
     * @dev This rotates the active registration namespace, invalidating previously cached registrations.
     */
    event WorldIDVerifierUpdated(address oldWorldIDVerifier, address newWorldIDVerifier);

    /**
     * @notice Emitted when the issuer schema id is updated.
     * @dev This rotates the active registration namespace, invalidating previously cached registrations.
     */
    event IssuerSchemaIdUpdated(uint64 oldIssuerSchemaId, uint64 newIssuerSchemaId);

    /**
     * @notice Emitted when the epoch duration is updated. This also signals
     *  a trigger on an immediate cache invalidation of all existing verifications.
     */
    event EpochDurationUpdated(uint64 oldEpochDuration, uint64 newEpochDuration);

    ////////////////////////////////////////////////////////////
    //                   EXTERNAL FUNCTIONS                   //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Registers an address for the current period.
     * @dev Any caller may register any `account`.
     */
    function register(address account, RegistrationProof calldata proof) external;

    /**
     * @notice Registers an address for the next period.
     * @dev Any caller may register any `account`.
     */
    function registerNextPeriod(address account, RegistrationProof calldata proof) external;

    /**
     * @notice Returns whether `account` is registered in the currently active period.
     */
    function isVerified(address account) external view returns (bool);

    /**
     * @notice Raw lookup for an explicit action.
     */
    function isVerifiedForAction(uint256 action, address account) external view returns (bool);

    /**
     * @notice Returns the currently active period index.
     */
    function getCurrentPeriod() external view returns (uint64);

    /**
     * @notice Returns the action derived for a specific period.
     */
    function getActionForPeriod(uint64 period) external view returns (uint256);

    /**
     * @notice Returns the action derived for the current period.
     */
    function getCurrentAction() external view returns (uint256);

    /**
     * @notice Returns the WorldID verifier address.
     */
    function getWorldIDVerifier() external view returns (address);

    /**
     * @notice Returns the configured epoch duration in seconds.
     */
    function getEpochDuration() external view returns (uint64);

    /**
     * @notice Returns the RP id configured on the contract.
     */
    function getRpId() external view returns (uint64);

    /**
     * @notice Returns the issuerSchemaId expected for proofs submitted to this contract.
     */
    function getIssuerSchemaId() external view returns (uint64);

    ////////////////////////////////////////////////////////////
    //                     OWNER FUNCTIONS                    //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Updates the WorldID verifier address.
     * @dev Existing registrations stop matching the active action namespace after a successful update.
     */
    function updateWorldIDVerifier(address newWorldIDVerifier) external;

    /**
     * @notice Updates the issuer schema id used for proof verification.
     * @dev Existing registrations stop matching the active action namespace after a successful update.
     */
    function updateIssuerSchemaId(uint64 newIssuerSchemaId) external;

    /**
     * @notice Updates the epoch duration used for period derivation.
     */
    function updateEpochDuration(uint64 newEpochDuration) external;
}
