---
name: acton
description: "Acton CLI workflow for TON smart contract development in Tolk: project bootstrap/init, Acton.toml config, build/compile/wrapper generation (including TypeScript), tests (coverage, gas snapshots, mutation, UI, fork/debug), scripts/deploy, wallets/libraries/local node, lint/format, inspection tools, verification, LSP/completions, and troubleshooting docs-vs-source mismatches."
---

# Acton TON CLI Workflow

## Use GitHub source, bundled references, and hosted docs in that order

- Prefer the current `ton-blockchain/acton` repo source and checked-in docs:
  - `https://github.com/ton-blockchain/acton/tree/master/docs/content/docs/commands`
  - `https://github.com/ton-blockchain/acton/blob/master/docs/content/docs/welcome.mdx`
  - `https://github.com/ton-blockchain/acton/blob/master/docs/content/docs/quickstart.mdx`
  - `https://github.com/ton-blockchain/acton/blob/master/docs/content/docs/project-init.mdx`
  - `https://github.com/ton-blockchain/acton/blob/master/docs/content/docs/acton-toml.mdx`
  - `https://github.com/ton-blockchain/acton/blob/master/docs/content/docs/build-system/configuration-reference.mdx`
  - `https://github.com/ton-blockchain/acton/blob/master/docs/content/docs/setup-wallets.mdx`
  - `https://github.com/ton-blockchain/acton/blob/master/docs/content/docs/contract-deployment.mdx`
  - `https://github.com/ton-blockchain/acton/blob/master/docs/content/docs/contract-verification.mdx`
  - `https://github.com/ton-blockchain/acton/tree/master/docs/content/docs/scripting`
  - `https://github.com/ton-blockchain/acton/tree/master/docs/content/docs/test-runner`
  - `https://github.com/ton-blockchain/acton/tree/master/docs/content/docs/local-development-node`
  - `https://github.com/ton-blockchain/acton/tree/master/docs/content/docs/linting`
  - `https://github.com/ton-blockchain/acton/tree/master/docs/content/docs/miscellaneous/ide-support`
  - `https://github.com/ton-blockchain/acton/blob/master/docs/content/docs/ci-setup.mdx`
  - `https://github.com/ton-blockchain/acton/blob/master/src/bin/acton.rs`
  - `https://github.com/ton-blockchain/acton/tree/master/src/commands`
  - `https://github.com/ton-blockchain/acton/blob/master/crates/acton-config/src/config.rs`
- If a local checkout of `ton-blockchain/acton` is available, use the equivalent local files for faster inspection.
- Read bundled skill references from this skill directory:
  - `references/command-map.md`
  - `references/troubleshooting.md`
- If no local Acton checkout is available, fall back to installed CLI help and official hosted docs:
  - `https://ton-blockchain.github.io/acton/docs/welcome/`
  - `https://ton-blockchain.github.io/acton/llms-full.txt`
- If CLI help or old examples still point at `https://i582.github.io/acton/...`, treat that as a legacy mirror. Prefer current source, local docs, and the `ton-blockchain.github.io` site.
- If current GitHub source, installed CLI help, and hosted docs disagree, trust them in this order:
  1. current source in `ton-blockchain/acton` (`src/bin/acton.rs`, command modules, `acton-config`)
  2. checked-in docs under `docs/content/docs/`
  3. `acton --help` / `acton <command> --help` from the exact binary/version being used
  4. hosted docs / `llms-full.txt`

## Known docs/source mismatches to watch for

- Some hosted/generated docs mention `hooks`, but the current source in this checkout does not expose an `acton hooks` command.
- Current source uses `acton up --canary`; some older docs still mention `--trunk`.
- Current source/help uses `acton test --coverage-format`; some docs still say `--format`.
- LiteNode defaults are not perfectly consistent across docs/help; verify current behavior from `src/bin/acton.rs` and `crates/acton-config/src/config.rs` before asserting a default port.

## Fast discovery workflow

1. Confirm project root and manifest resolution:
   - `pwd`
   - `acton doctor`
   - `acton --project-root <PATH> ...` or `--manifest-path <PATH>` when working outside the project directory
2. Confirm command and flag spelling from current source or help:
   - if you are inside the Acton repo: `cargo run --bin acton -- --help`
   - if you are using an installed CLI: `acton --help`
   - for subcommands: `cargo run --bin acton -- <command> --help` or `acton <command> --help`
   - or inspect `src/bin/acton.rs`
3. Open the matching docs page in `https://github.com/ton-blockchain/acton/tree/master/docs/content/docs/` before answering from memory, or use the equivalent local checkout path when available.
4. If docs are thin or stale, read the implementing command module in `https://github.com/ton-blockchain/acton/tree/master/src/commands`, or rely on the exact binary’s help output if source is unavailable.

## Modern Acton surface area

### Project bootstrap and configuration

- Use `acton new <path> [--template empty|counter|jetton]` for new projects.
- Use `acton init` to add Acton to an existing directory:
  - creates or patches `Acton.toml`
  - discovers contracts by `onInternalMessage`
  - ensures default mappings
  - patches `.gitignore`
  - installs `.acton` stdlib and symlinks global wallets/libraries when available
- Current built-in templates in source are only:
  - `empty`
  - `counter`
  - `jetton`
- `acton new` currently seeds:
  - `Acton.toml`
  - `.acton/`
  - `.env`
  - `.editorconfig`
  - default `[scripts]` entries such as `deploy-emulation` and `deploy-testnet`
- Important `Acton.toml` sections to inspect and use:
  - `[contracts]`
  - `[build]`
  - `[wrappers.tolk]`
  - `[wrappers.typescript]`
  - `[test]`
  - `[lint]`
  - `[fmt]`
  - `[litenode]`
  - `[networks]`
  - `[scripts]`
  - `[mappings]`

### Build, compile, and wrapper generation

- `acton build [contract-id]`
  - `--clear-cache`
  - `--graph [deps.dot]`
  - `--out-dir <dir>`
  - `--gen-dir <dir>`
  - `--output-fift <dir>`
  - `--info`
- `acton compile <file.tolk>`
  - `--json`
  - `--base64-only`
  - `--boc <file>`
  - `--fift <file>`
  - `--source-map <file>`
  - `--abi <file>`
  - `--clear-cache`
- `acton wrapper <contract-id>`
  - generates Tolk wrappers from contract ABI
  - `--test`, `--test-output`, `--test-output-dir` generate test stubs
  - `--ts` generates a TypeScript wrapper via `gen-typescript-from-tolk-dev`
  - wrapper defaults come from `[wrappers.tolk]` and `[wrappers.typescript]`
- Wrapper generation depends on contract header ABI:
  - `storage: ...`
  - `incomingMessages: ...`
- If the user wants frontend or client integration, prefer `acton wrapper <contract> --ts` over hand-written TypeScript wrappers.

### Tests, profiling, UI, and quality gates

- Core test entrypoint: `acton test [path]`
- Common test flags:
  - `--filter <regex>`
  - `--include <glob>`
  - `--exclude <glob>`
  - `--fail-fast`
  - `--debug --debug-port <port>`
  - `--backtrace full`
  - `--reporter console|dot|teamcity|junit`
  - `--show-bodies`
  - `--clear-cache`
- Coverage:
  - `acton test --coverage --coverage-format lcov`
  - `--coverage-file <path>` for explicit output path
- Gas profiling and regression checks:
  - `acton test --snapshot gas-baseline.json`
  - `acton test --baseline-snapshot gas-baseline.json`
  - `acton test --baseline-snapshot gas-baseline.json --fail-on-diff`
- Mutation testing:
  - `acton test --mutate --mutate-contract <contract-id>`
  - `--disable-rule <RULE>`
  - defaults can be configured under `[test.mutation]`
- Fork testing and remote state:
  - `acton test --fork-net testnet|mainnet|custom:<name>`
  - `--fork-block-number <seqno>`
  - `--api-key <TONCENTER_API_KEY>`
- Test UI:
  - `acton test --ui`
  - `acton test --ui --ui-port 23456`
  - use it to inspect failed tests, fee summaries, transaction trees, out actions, and executor or VM logs
- Trace export:
  - `acton test --save-test-trace`
  - `acton test --save-test-trace .acton/traces`
- Project defaults live in `[test]` in `Acton.toml`; CLI flags override config.

### Linting and formatting

- `acton check [target]`
  - project-wide, contract-id, or single file
  - `--fix`
  - `--output-format plain|json|sarif|github|gitlab`
  - `--output-file <path>`
  - `--enable-only E001,S001`
  - `--explain <CODE>`
- Lint policy comes from:
  - `[lint]`
  - `[lint.rules]`
  - `[lint.rules.<contract-id>]`
  - inline suppressions: `// acton-disable-next-line ...`
- `acton fmt [paths...]`
  - `--check`
  - config lives in `[fmt]`
  - formatter supports import grouping and ignore globs
- For CI, commonly pair:
  - `acton check --output-format github`
  - `acton fmt --check`
  - `acton test --reporter console,junit`
  - `acton test --coverage --coverage-format lcov`

### Scripts, deployment, and blockchain interaction

- `acton script <path> [args...]` runs standalone Tolk scripts.
- Prefer the safe execution sequence:
  1. `acton build`
  2. `acton test`
  3. `acton script <path>` without `--broadcast`
  4. only then `acton script <path> --broadcast --net testnet|mainnet|localnet`
- Script flags to remember:
  - `--debug`, `--debug-port`
  - `--clear-cache`
  - `--fork-net`
  - `--fork-block-number`
  - `--api-key`
  - `--broadcast`
  - `--net testnet|mainnet|localnet|custom:<name>`
  - `--explorer tonscan|toncx|dton|tonviewer`
  - `--show-bodies`
- `acton run <script-name> [-- extra args]` executes entries from `[scripts]` in `Acton.toml`.
- There is still no `acton deploy` command. Deployment is script-driven by design.
- In scripts:
  - `net.wallet("<name>")` maps to real wallets only under `--broadcast`
  - without `--broadcast`, Acton emulates with local wallets
  - use `result.wait()` for broadcast confirmation
  - use `--fork-net` to query real chain state in read paths

### Wallets, verification, libraries, and local node

- Wallet subcommands:
  - `acton wallet new`
  - `acton wallet import`
  - `acton wallet list`
  - `acton wallet export-mnemonic`
  - `acton wallet sign`
  - `acton wallet remove`
  - `acton wallet airdrop`
- Wallet guidance:
  - prefer secure keyring storage when available
  - use `mnemonic-env` for CI and automation
  - treat `wallets.toml` and `global.wallets.toml` as sensitive
  - configure expected addresses for safety
- Verification:
  - `acton verify [contract-id] --address <addr>`
  - `--net testnet|mainnet`
  - `--wallet <name>`
  - `--compiler-version <ver>`
  - `--dry-run`
  - `--api-key`
- Libraries:
  - `acton library publish`
  - `acton library fetch`
  - `acton library info`
  - `acton library topup`
- Local development node:
  - `acton litenode start`
  - `acton litenode airdrop <address>`
  - supports fork mode, historical block pinning, startup account bootstrap, rate limiting, SQLite persistence, JSON snapshots, and local faucet workflows
  - defaults are configurable in `[litenode]`
  - custom and local networks are configured in `[networks]`

### Inspection, low-level tooling, and developer UX

- `acton disasm`
  - disassemble BoC files or live contract code
  - use `--source-map`, `--show-offsets`, `--show-hashes`, `--follow-libraries`
- `acton retrace <tx-hash>`
  - replay on-chain transactions locally
  - `--verbose`
  - `--logs-dir`
- `acton doc tvm <query...>`
  - exact or fuzzy TVM instruction lookup
- `acton ls`
  - runs the TON and Tolk LSP server
  - use `--stdio` or `--port`
  - optional log file
- `acton doctor`
  - inspect resolved project root, manifest, stdlib, overlays, env vars, and writable paths
- `acton func2tolk <path>`
  - shells out to `npx @ton/convert-func-to-tolk@1.0.0`
  - requires Node.js, npm, and `npx`
- `acton up`
  - version management
  - current source supports `--list`, `--canary`, `--stable`, `--yes`
- `acton completions <shell>`
  - static completions
  - dynamic completions also exist via `COMPLETE=<shell> acton`

## Practical defaults when helping users

- Start with:
  - `acton doctor`
  - `acton build`
  - `acton test`
- If imports, resolution, or config are involved, inspect:
  - `Acton.toml`
  - `[mappings]`
  - `[networks]`
  - `crates/acton-config/src/config.rs`
- If wrappers, tests, or scripts fail after ABI changes, regenerate wrappers instead of hand-editing old ones.
- If the user is building a client or frontend, prefer TypeScript wrapper generation.
- If they need end-to-end local flows, prefer `acton litenode start` plus `--net localnet`.
- If they need CI guidance, include `check`, `fmt --check`, `test`, JUnit, coverage, and SARIF or GitHub outputs.
- If they need editor integration, mention `acton ls` and the IDE support docs.

## Safety and correctness rules

- Warn once before any `--broadcast`, `verify`, `library publish`, or `library topup` action that can spend real TON.
- State wallet, network, and project-root assumptions explicitly.
- Do not invent commands that are not in current source.
- When a command or flag seems odd, verify it in `src/bin/acton.rs` before answering.
- When docs and source disagree, say so explicitly and follow current source.
- Use TON docs only for blockchain concepts that Acton docs do not cover.
