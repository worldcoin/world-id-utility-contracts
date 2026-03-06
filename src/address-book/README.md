# AddressBook

`AddressBook` is an action-scoped soft-cache for World ID proof verification results. It also acts as its own RP, using a single `rpId` configured at initialization.

## Core model

- Context: `EpochData { action }`
- Active period: computed as UTC calendar months from `periodStartTimestamp`
- `periodStartTimestamp` must be the first second of a UTC month (`YYYY-MM-01 00:00:00 UTC`)
- Date conversion and month arithmetic are implemented in `libraries/DateTimeLib.sol`
- Storage key: `epochId = keccak256(abi.encode(period, action))`
- `targetPeriod` is part of the storage key at registration time

## Registration

`register(account, targetPeriod, epoch, proof)` verifies the World ID proof and stores the result under
`epochId(targetPeriod, epoch)`.

`proof` carries the verifier public inputs needed by `WorldIDVerifier`, except `rpId`, which is read from contract state.

Constraints:

- one nullifier per `(period, action)` epoch key
- one address per `(period, action)` epoch key
- optional registration guard for current/next period only
- `proof.expiresAtMin` must cover the full target period:
  - `expiresAtMin >= firstSecondOfUtcMonth(targetPeriod + 1)`

## Verification

`verify(epoch, account)` enforces a valid current period, then performs a period+action scoped lookup:

- compute `currentPeriod`
- lookup `epochId(currentPeriod, epoch)`

Because `period` is part of `epochId`, verification naturally rolls over by period.

## Signal binding

The canonical UTF-8 signal string is just the registered account address hex string:

`signal = "<accountHex>"`

`signalHash = uint256(keccak256(bytes(signal))) >> 8`

This matches the authenticator path (`RequestItem.signal` -> hash raw UTF-8 bytes) and binds the proof to the registered account.

## Security Invariants

1. **Per-period+action nullifier uniqueness**
- A nullifier can be consumed only once within the same `epochId` (period, action).

2. **Per-period+action address uniqueness**
- The same account cannot be re-registered in the same `epochId` (period, action).

3. **Proof/account binding**
- `signalHash` binds the proof to the registered account.

4. **Permissionless registration**
- Third parties may register an account if they provide a valid proof bound to that account signal.

5. **Target-period expiry floor**
- Registration requires `expiresAtMin` to be at least the end of the target period.

## E2E example

Assume:

- `periodStartTimestamp = 2025-01-01 00:00:00 UTC`
- `epoch = EpochData { action: A_JAN }`
- current period at start is `P=10` (January)

### 1) Initial registration in January

1. A prover gets a valid World ID uniqueness proof for `(rpId=addressBook.rpId, action=A_JAN)` and `signal = userAddress`.
2. Any caller can submit registration:
   - `register(userAddress, 10, epoch, proof)`
3. Contract verifies proof through `WorldIDVerifier.verify(...)` and stores:
   - `registered[epochId(10, A_JAN)][userAddress] = true`
4. Contract enforces `proof.expiresAtMin` is at least the end of period `10`.

### 2) Repeated checks in January

1. RP calls:
   - `verify(epoch, userAddress)`
2. Contract computes current period (`10`) and checks `epochId(10, A_JAN)`.
3. Result is `true` with a cheap storage lookup (no new full proof verification).

### 3) February rollover

1. Time moves forward by one period; now current period is `11`.
2. RP calls again:
   - `verify(epoch, userAddress)`
3. Contract now checks `epochId(11, A_JAN)`.
4. Result is `false` unless user also registered for period `11`.

### 4) Pre-register next period

If pre-registration is enabled by policy:

1. During period `10`, user can register for period `11`:
   - `register(userAddress, 11, EpochData{action: A_FEB}, proofForAFEB)`
2. Before rollover, `verify(EpochData{A_FEB}, userAddress)` is `false` because current period is still `10`.
3. After rollover to period `11`, the same call returns `true`.

Notes:

- If `enforceCurrentOrNextPeriod` is `true`, registering for period `12+` while current is `10` reverts.
- The contract treats `action` as provided by the RP flow.
- The contract always verifies against its configured `rpId`; callers do not choose the RP per registration.
