# Command Map

Use this file for fast command selection before opening full docs.

## Bootstrap and config

- `acton new <PATH> [--template empty|counter|jetton]`
- Use for scaffolding a fresh project with templates, scripts, wrappers, `.env`, and default mappings.

- `acton init`
- Use for adding Acton to an existing directory, discovering contracts, patching `.gitignore`, and installing `.acton`.

- `acton doctor`
- Use for project-root, manifest, stdlib, overlay, and writable-path diagnostics.

## Build and wrapper generation

- `acton build [CONTRACT_ID] [--clear-cache] [--graph [PATH]] [--out-dir DIR] [--gen-dir DIR] [--output-fift DIR] [--info]`
- Use for contract builds from `Acton.toml`.

- `acton compile <PATH> [--json] [--base64-only] [--boc FILE] [--fift FILE] [--source-map FILE] [--abi FILE] [--clear-cache]`
- Use for single-file compilation and artifact extraction.

- `acton wrapper <CONTRACT_ID> [--output PATH|--output-dir DIR] [--test] [--test-output PATH|--test-output-dir DIR]`
- Use for Tolk wrapper generation and bootstrapping test stubs.

- `acton wrapper <CONTRACT_ID> --ts [--output PATH|--output-dir DIR]`
- Use for TypeScript client wrapper generation.

## Tests and quality

- `acton test [PATH] [--filter REGEX] [--include GLOB] [--exclude GLOB] [--reporter console|dot|teamcity|junit]`
- Use for normal test runs.

- `acton test --coverage --coverage-format lcov [--coverage-file PATH]`
- Use for code coverage and LCOV export.

- `acton test --snapshot gas-baseline.json`
- Use for creating gas and fee baselines.

- `acton test --baseline-snapshot gas-baseline.json [--fail-on-diff]`
- Use for gas regression checks.

- `acton test --mutate --mutate-contract <contract-id> [--disable-rule RULE]`
- Use for mutation testing.

- `acton test --debug --debug-port 8080 [--backtrace full]`
- Use for debugger-based diagnosis.

- `acton test --ui [--ui-port 23456]`
- Use for browser-based inspection of failed tests, traces, transactions, and logs.

- `acton test --fork-net testnet|mainnet|custom:<name> [--fork-block-number N] [--api-key KEY]`
- Use for forked-state tests against remote chain data.

- `acton check [TARGET] [--fix] [--output-format plain|json|sarif|github|gitlab] [--output-file PATH]`
- Use for linting Tolk code and CI annotations.

- `acton fmt [PATHS...] [--check]`
- Use for formatting or CI format validation.

## Scripts, deployment, and blockchain interaction

- `acton script <PATH> [ARGS...]`
- Use for local script execution and safe dry runs.

- `acton script <PATH> --broadcast [--net testnet|mainnet|localnet|custom:<name>] [--api-key KEY] [--explorer tonscan|toncx|dton|tonviewer]`
- Use for real network transactions; can spend TON.

- `acton script <PATH> --fork-net testnet|mainnet|custom:<name> [--fork-block-number N]`
- Use for read paths against live remote state without broadcasting.

- `acton run <script-name> [-- extra args]`
- Use for shortcuts defined under `[scripts]` in `Acton.toml`.

## Wallets, verification, libraries, and local node

- `acton wallet new|import|list|export-mnemonic|sign|remove|airdrop`
- Use for wallet lifecycle and faucet flows.

- `acton verify [CONTRACT_ID] --address <ADDRESS> [--net testnet|mainnet] [--wallet NAME] [--compiler-version VER] [--dry-run]`
- Use for source verification against verifier.ton.org.

- `acton library publish|fetch|info|topup`
- Use for on-chain library lifecycle tasks.

- `acton litenode start [--port PORT] [--fork-net NET] [--fork-block-number N] [--accounts a,b] [--db-path PATH] [--load-state PATH] [--dump-state PATH] [--rate-limit RPS]`
- Use for local TON-compatible node workflows, fork mode, snapshots, and startup wallets.

- `acton litenode airdrop <ADDRESS> [--amount TON] [--port PORT]`
- Use for localnet faucet funding.

## Inspection and developer tooling

- `acton disasm [BOC_FILE] [--address ADDRESS] [--net NET] [--source-map FILE] [--show-offsets] [--show-hashes] [--follow-libraries]`
- Use for BoC and live-code disassembly.

- `acton retrace <TX_HASH> [--net NET] [--api-key KEY] [--verbose] [--logs-dir DIR]`
- Use for replaying on-chain transactions locally.

- `acton doc tvm <QUERY...> [--find] [--description] [--json]`
- Use for TVM instruction lookup.

- `acton ls [--stdio|--port PORT] [--log-file PATH] [--no-log]`
- Use for TON/Tolk language-server workflows.

- `acton func2tolk <PATH> [--output PATH] [--warnings-as-comments] [--no-camel-case]`
- Use for quick FunC-to-Tolk conversion via the npm-based converter.

- `acton up [VERSION] [--list] [--canary] [--stable] [--yes]`
- Use for version management. Prefer `--canary` over any older `--trunk` examples.

- `acton completions <SHELL>`
- Use for static shell completion generation.
