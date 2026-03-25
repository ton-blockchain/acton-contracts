# Repo examples: `contracts_FunC/` -> `contracts_Tolk/`

Use this file when you have access to a paired porting corpus such as `tolk-bench` or any local repo that mirrors legacy FunC contracts beside rewritten Tolk equivalents.

Canonical paired layout:

- `<paired-porting-repo>/contracts_FunC/NN_*` — original FunC sources (`.fc` / `.func`)
- `<paired-porting-repo>/contracts_Tolk/NN_*` — rewritten Tolk sources (`.tolk`) following a consistent module layout

## Common module layout in `<paired-porting-repo>/contracts_Tolk/*`

- `errors.tolk` — error code constants
- `messages.tolk` — TL-B message structs with opcode tags + union types
- `storage.tolk` — storage structs + `load/save` helpers
- `fees-management.tolk` / `jetton-utils.tolk` / etc — shared logic split out for reuse
- `*-contract.tolk` — contract entrypoints (`onInternalMessage`, `onBouncedMessage`, `onExternalMessage`) + getters

## Example directories to study (by pattern)

- Jettons (minter/wallet + bounce restore patterns):
  - `<paired-porting-repo>/contracts_FunC/01_jetton/`
  - `<paired-porting-repo>/contracts_Tolk/01_jetton/`
- NFT (uninitialized vs initialized storage pattern):
  - `<paired-porting-repo>/contracts_FunC/02_nft/`
  - `<paired-porting-repo>/contracts_Tolk/02_nft/`
- Wallet v5 (external signature parsing + C5 actions):
  - `<paired-porting-repo>/contracts_FunC/05_wallet-v5/`
  - `<paired-porting-repo>/contracts_Tolk/05_wallet-v5/`

## Additional baselines to use when present in the workspace

- DNS FunC baseline:
  - a sibling or linked repo with `func/`
- Highload v3 FunC baseline:
  - a file such as `contracts/highload-wallet-v3.func`
- Rewritten Acton/Tolk targets in `ton-blockchain/acton-contracts`:
  - `https://github.com/ton-blockchain/acton-contracts/tree/main/acton-jetton/contracts`
  - `https://github.com/ton-blockchain/acton-contracts/tree/main/dns/contracts`
  - `https://github.com/ton-blockchain/acton-contracts/tree/main/nft/contracts`
  - `https://github.com/ton-blockchain/acton-contracts/tree/main/highload-v3/contracts`

## Useful search keys

- Opcodes: search for the hex (for example `0xd53276db`).
- Message type names: search for `struct (` in Tolk and `op::` in FunC.
- Storage fields: search for the field name in `storage.tolk` and the corresponding `load_data` logic in FunC.
