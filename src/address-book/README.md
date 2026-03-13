# AddressBook

`AddressBook` is a period-scoped soft-cache for World ID proof verification results. Each deployment acts as its own RP: it is initialized with a single non-zero `rpId`, and it derives exactly one valid World ID action for each monthly period.

## Core model

- `periodStartTimestamp` defines period `0` and must be the first second of a UTC month (`YYYY-MM-01 00:00:00 UTC`)
- each period is one UTC calendar month
- each period has exactly one action, derived deterministically by the contract
- callers do not choose the RP id or the action
- storage is period-scoped:
  - `registered[period][account]`
  - `nullifierUsed[period][nullifier]`

## Action derivation

The action for a period is derived as a World ID field element using the same reduction rule used in the protocol primitives for arbitrary bytes:

```text
action(period) = uint256(keccak256(
  abi.encodePacked("WORLD_ID_ADDRESS_BOOK_ACTION", address(this), period)
)) >> 8
```

This gives each address-book deployment its own monthly action schedule while keeping every action inside the field.

Use:

- `getCurrentAction()` for the current period
- `getActionForPeriod(period)` for an explicit period

A frontend or prover should query one of these helpers before generating the proof.

## Public API

### Register current period

```solidity
register(address account, RegistrationProof proof)
```

Verifies the proof against:

- `rpId` stored in the contract
- the action derived for the current period
- the canonical signal derived from `account`

On success, the contract marks `account` and `nullifier` as used for the current period.

### Register next period

```solidity
registerNextPeriod(address account, RegistrationProof proof)
```

Same flow as `register`, but it targets `currentPeriod + 1`. This allows pre-registration for the next month without exposing arbitrary period selection in the public API.

### Verify current period

```solidity
verify(address account) -> bool
```

Returns whether `account` is registered for the current period.

### Raw historical lookup

```solidity
isRegisteredForPeriod(uint32 period, address account) -> bool
```

Returns whether `account` was registered for a specific period.

## Registration rules

A registration succeeds only if all of the following hold:

- `account != address(0)`
- `rpId != 0` at initialization
- the proof expiry covers the full target period:
  - `proof.expiresAtMin >= periodEndTimestamp(periodStartTimestamp, targetPeriod)`
- the nullifier has not already been used in the target period
- the account has not already been registered in the target period
- `WorldIDVerifier.verify(...)` accepts the proof for the derived `(rpId, action, signalHash)` tuple

## Signal binding

The canonical signal is the lowercase hex string form of the registered account:

```text
signal = Strings.toHexString(uint256(uint160(account)), 20)
signalHash = uint256(keccak256(bytes(signal))) >> 8
```

This binds the proof to the account being registered. Any caller may submit the transaction, but the proof must still be generated for that specific account signal.

## Period rollover

Verification is period-scoped by design:

- if a user registers in the current month, `verify(account)` returns `true` for the rest of that month
- when the month rolls over, `verify(account)` switches to the new current period
- to remain valid in the new month, the user must register again for that month, either after rollover with `register(...)` or before rollover with `registerNextPeriod(...)`
