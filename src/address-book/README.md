# AddressBook

`AddressBook` is a period-scoped soft-cache for World ID proof verification results. Each deployment acts as its own RP: it is initialized with a single non-zero `rpId`, and it derives exactly one valid World ID action for each fixed-duration period.

## Core model

- `epochDuration` defines the period length in seconds
- the current period is `uint64(block.timestamp / epochDuration)`
- the owner may update `epochDuration`, and the new value takes effect immediately
- each period has exactly one action, derived deterministically by the contract
- callers do not choose the RP id or the action
- storage is action-scoped:
  - `registered[action][account]`
  - `nullifierUsed[action][nullifier]`

## Action derivation

The action for a period is derived as a World ID field element using the same reduction rule used in the protocol primitives for arbitrary bytes:

```text
action(period, epochDuration) = uint256(keccak256(
  abi.encodePacked(uint256(period), epochDuration)
)) >> 8
```

This makes the action unique to the `(period, epochDuration)` pair while keeping the result inside the field.

Use:

- `getCurrentAction()` for the current period
- `getActionForPeriod(period)` for an explicit period under the currently configured `epochDuration`

A frontend or prover should query one of these helpers immediately before generating the proof.

## Public API

### Register current period

```solidity
register(address account, RegistrationProof proof)
```

Verifies the proof against:

- `rpId` stored in the contract
- the action derived for the current period
- the canonical signal derived from `account`

On success, the contract marks `account` and `nullifier` as used for that derived action.

### Register next period

```solidity
registerNextPeriod(address account, RegistrationProof proof)
```

Same flow as `register`, but it targets `currentPeriod + 1` using the currently configured `epochDuration`.

### Verify current period

```solidity
verify(address account) -> bool
```

Returns whether `account` is registered for the action derived from the currently active period.

### Raw historical lookup

```solidity
isRegisteredForAction(uint256 action, address account) -> bool
```

Returns whether `account` was registered for a specific derived action.

## Registration rules

A registration succeeds only if all of the following hold:

- `account != address(0)`
- `rpId != 0` at initialization
- `issuerSchemaId != 0` at initialization
- `epochDuration != 0` at initialization and on updates
- the proof expiry covers the full target period:
  - `proof.expiresAtMin >= (uint256(targetPeriod) + 1) * epochDuration`
- the nullifier has not already been used for the derived action
- the account has not already been registered for the derived action
- `WorldIDVerifier.verify(...)` accepts the proof for the derived `(rpId, action, signalHash)` tuple

## Signal binding

The canonical signal hash is:

```text
signalHash = uint256(keccak256(abi.encodePacked(account))) >> 8
```

This binds the proof to the account being registered. Any caller may submit the transaction, but the proof must still be generated for that specific account signal.

## Duration updates

Updating `epochDuration` takes effect immediately:

- `getCurrentPeriod()` is recomputed as `block.timestamp / epochDuration`
- `getCurrentAction()` changes immediately
- `verify(account)` switches to the action derived from the new duration immediately
- old registrations remain stored under their old action and can still be queried through `isRegisteredForAction(...)`

## Period rollover

Verification is period-scoped by design:

- if a user registers in the current period, `verify(account)` returns `true` until the current period boundary
- when the period rolls over, `verify(account)` switches to the new current action
- to remain valid in the new period, the user must register again for that period, either after rollover with `register(...)` or before rollover with `registerNextPeriod(...)`
