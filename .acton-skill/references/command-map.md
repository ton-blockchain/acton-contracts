# Command Map

Use this file for fast command selection before opening full docs.

## Project setup

- `acton new <PATH> [--template empty|counter|jetton] [--license MIT] [--desc "..."]`
- Use for scaffolding a new project layout with `Acton.toml`, contracts, tests, and scripts.

## Build pipeline

- `acton build [CONTRACT] [--clear-cache] [--graph [PATH]] [--out-dir DIR]`
- Use for project-level contract compilation from `Acton.toml`.

- `acton compile <PATH> [--json] [--base64-only] [--boc FILE] [--fift FILE] [--source-map FILE]`
- Use for single-file compilation and direct artifact output.

## Testing

- `acton test [PATH] [--filter REGEX] [--reporter console|junit|teamcity]`
- Use for normal test runs.

- `acton test --coverage [--format lcov]`
- Use for code coverage.

- `acton test --mutate --mutate-contract <contract-id> [--disable-rule RULE]`
- Use for mutation testing quality checks.

- `acton test --debug --debug-port 8080`
- Use for debugger-based diagnosis.

## Scripting and deployment

- `acton script <PATH>`
- Use for local emulation and dry-run behavior.

- `acton script <PATH> --broadcast [--net testnet|mainnet] [--api-key KEY]`
- Use for real network transactions; can spend TON.

- `acton run <script-name> [-- extra args]`
- Use for commands wrapped under `[scripts]` in `Acton.toml`.

## Wallet operations

- `acton wallet new [--name NAME] [--local|--global] [--version VERSION]`
- `acton wallet import [--name NAME] [--local|--global] "<mnemonic>"`
- `acton wallet list [--balance] [--api-key KEY]`
- `acton wallet get <name>`

Prefer secure keyring-backed mnemonic storage where possible.

## Verification

- `acton verify <contract> --address <address> [--net testnet|mainnet] [--wallet NAME]`
- `acton verify <contract> --address <address> --dry-run`
- `acton verify <contract> --address <address> --compiler-version <version>`

Use `--api-key` to avoid TonCenter rate-limit waits.

## Library lifecycle

- `acton library publish [CONTRACT_ID] [--duration 365d] [--wallet NAME] [--net testnet|mainnet]`
- `acton library fetch <HASH> [--disasm] [-o FILE] [--json]`
- `acton library info [LIBRARY_NAME]`
- `acton library topup [LIBRARY_NAME] [--duration 1y|--amount TON]`

Use for shared on-chain library distribution and maintenance.
