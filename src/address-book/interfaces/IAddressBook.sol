// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IAddressBook
 * @author World Contributors
 * @notice Period-scoped soft-cache for World ID verification results, acting as its own RP.
 */
interface IAddressBook {
    ////////////////////////////////////////////////////////////
    //                        STRUCTS                         //
    ////////////////////////////////////////////////////////////

    /**
     * @notice World ID proof payload needed for registration.
     * @dev The RP id and action are configured/derived by the contract and are not supplied per proof.
     */
    struct RegistrationProof {
        uint256 nullifier;
        uint256 nonce;
        uint64 expiresAtMin;
        uint64 issuerSchemaId;
        uint256 credentialGenesisIssuedAtMin;
        uint256[5] zeroKnowledgeProof;
    }

    ////////////////////////////////////////////////////////////
    //                        ERRORS                          //
    ////////////////////////////////////////////////////////////

    /// @notice Thrown when `periodStartTimestamp` is not the first second of a UTC calendar month.
    /// @param periodStartTimestamp The invalid start timestamp.
    error InvalidPeriodStartTimestamp(uint64 periodStartTimestamp);

    /// @notice Thrown when registration/verification is attempted before period 0 start.
    error PeriodNotStarted();

    /// @notice Thrown when computed period does not fit into `uint32`.
    error PeriodOutOfRange();

    /// @notice Thrown when `register` is called with the zero address as `account`.
    error InvalidAccount();

    /// @notice Thrown when proof expiry does not cover the full target period.
    /// @param expiresAtMin The expiry bound carried in the proof.
    /// @param periodEnd The required minimum expiry for the target period end.
    error ExpirationBeforePeriodEnd(uint64 expiresAtMin, uint256 periodEnd);

    /// @notice Thrown when an RP id of `0` is provided where a configured RP id is required.
    error InvalidRpId();

    /// @notice Thrown when a nullifier was already consumed for the same period.
    /// @param nullifier The duplicate nullifier.
    /// @param period The period where the nullifier was already used.
    error NullifierAlreadyUsed(uint256 nullifier, uint32 period);

    /// @notice Thrown when an address is already registered for the same period.
    /// @param account The duplicate account.
    /// @param period The period where the account is already registered.
    error AddressAlreadyRegistered(address account, uint32 period);

    ////////////////////////////////////////////////////////////
    //                        EVENTS                          //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Emitted when an address is registered for a period.
     */
    event AddressRegistered(uint32 indexed period, address indexed account, uint256 action, uint256 nullifier);

    /**
     * @notice Emitted when the WorldID verifier contract is updated.
     */
    event WorldIDVerifierUpdated(address oldWorldIDVerifier, address newWorldIDVerifier);

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
    function verify(address account) external view returns (bool);

    /**
     * @notice Raw lookup for an explicit period.
     */
    function isRegisteredForPeriod(uint32 period, address account) external view returns (bool);

    /**
     * @notice Returns the currently active period index.
     */
    function getCurrentPeriod() external view returns (uint32);

    /**
     * @notice Returns the action derived for a specific period.
     */
    function getActionForPeriod(uint32 period) external view returns (uint256);

    /**
     * @notice Returns the action derived for the current period.
     */
    function getCurrentAction() external view returns (uint256);

    /**
     * @notice Computes the canonical signal string for `account`.
     */
    function computeSignal(address account) external view returns (string memory);

    /**
     * @notice Computes the signal hash bound to `account`.
     */
    function computeSignalHash(address account) external view returns (uint256);

    /**
     * @notice Returns the WorldID verifier address.
     */
    function getWorldIDVerifier() external view returns (address);

    /**
     * @notice Returns the configured period start timestamp.
     * @dev This must be the first second of a UTC calendar month.
     */
    function getPeriodStartTimestamp() external view returns (uint64);

    /**
     * @notice Returns the RP id configured on the contract.
     */
    function getRpId() external view returns (uint64);

    ////////////////////////////////////////////////////////////
    //                     OWNER FUNCTIONS                    //
    ////////////////////////////////////////////////////////////

    /**
     * @notice Updates the WorldID verifier address.
     */
    function updateWorldIDVerifier(address newWorldIDVerifier) external;
}
