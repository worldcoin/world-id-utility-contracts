# AddressBook

`AddressBook` is a period-scoped cache for World ID proof verification results.

Each deployment acts as its own relying party. The contract fixes the `rpId`, derives the valid World ID action for each epoch, verifies a proof once, and then stores whether an address is valid for that period. Consumers can then check `isVerified(account)` for the current period or `isVerifiedForAction(action, account)` for an explicit action instead of re-verifying a full proof on every integration path.

That makes the contract useful when an application needs:

- a simple onchain membership check for the current period
- cheaper and easier downstream integrations that only need a boolean status

The detailed behavior lives in the Solidity source and tests:

- `AddressBook.sol` contains the registration flow, period/action derivation, and admin controls
- `IAddressBook.sol` defines the external surface
- `AddressBook.t.sol` covers the expected lifecycle and edge cases
