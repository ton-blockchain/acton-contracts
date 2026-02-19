---
name: acton
description: "Acton CLI workflow for TON smart contract development in Tolk: scaffold projects, configure Acton.toml contracts/dependencies/mappings, compile/build contracts, run tests (coverage/mutation/debug), write/run scripts, manage wallets, deploy with broadcast, verify source on-chain, and manage on-chain libraries. Use when requests involve acton commands, .tolk contracts, Acton.toml, deployment, verification, wallets, testnet/mainnet, Jetton templates, or troubleshooting Acton output."
---

# Acton TON CLI Workflow

## Use repository docs as source of truth

- Use absolute paths for local Acton docs in this environment:
  - `/Users/kaladin/work/core/acton/docs/content/docs/commands/*.mdx`
  - `/Users/kaladin/work/core/acton/docs/content/docs/quickstart.mdx`
  - `/Users/kaladin/work/core/acton/docs/content/docs/contract-deployment.mdx`
  - `/Users/kaladin/work/core/acton/docs/content/docs/contract-verification.mdx`
  - `/Users/kaladin/work/core/acton/docs/content/docs/build-system/configuration-reference.mdx`
  - `/Users/kaladin/work/core/acton/docs/content/docs/scripting/setup-wallets.mdx`
- Read skill references via absolute paths:
  - `/Users/kaladin/.codex/skills/acton/references/command-map.md`
  - `/Users/kaladin/.codex/skills/acton/references/troubleshooting.md`
- For complete hosted Acton capability coverage, fetch and search:
  - `https://i582.github.io/acton/llms-full.txt`
  - Use this as a high-coverage reference for commands, utilities, and behaviors not obvious from local files.
- For extended hosted documentation, search:
  - `https://i582.github.io/acton/docs/quickstart/`
  - Then navigate to related pages under `https://i582.github.io/acton/docs/`.
- Use TON Docs only for protocol concepts not covered by Acton docs.

## Use docs-first lookup when uncertain

- Start with local docs under `/Users/kaladin/work/core/acton/docs/content/docs/`.
- If the repository is checked out in a different location, use `pwd` and substitute that absolute root in all paths above.
- If coverage is incomplete, query hosted Acton references before guessing:

```bash
curl -fsSL https://i582.github.io/acton/llms-full.txt | rg -n "keyword|command|flag"
```

```bash
curl -fsSL https://i582.github.io/acton/docs/quickstart/
```

- Prefer these hosted Acton sources over generic web search for Acton-specific behavior.

## Run the default safe sequence

1. Confirm `Acton.toml` exists in the project root.
2. Build contracts with `acton build` or `acton build <contract>`.
3. Run tests with `acton test`.
4. Run scripts locally first: `acton script <path>` (without `--broadcast`).
5. Broadcast only after local success: `acton script <path> --broadcast --net testnet|mainnet`.
6. Verify deployed source: `acton verify <contract> --address <address> [--net ...]`.

## Initialize projects

- Scaffold with template:

```bash
acton new my-project --template counter
```

- Select template by goal:
  - `empty` for minimal scaffolding.
  - `counter` for starter contract + tests + deploy script.
  - `jetton` for multi-contract token architecture.

- Validate baseline after scaffolding:

```bash
cd my-project
acton build
acton test
```

## Build and compile

- Use `acton build` for contracts declared in `Acton.toml`.
- Use `acton compile <file.tolk>` for one-off compiler output.
- Use advanced build flags only when needed:
  - `acton build --clear-cache`
  - `acton build --graph [path.svg]`
  - `acton build --out-dir artifacts/`

## Run tests in the right mode

- Run suite: `acton test`
- Filter cases: `acton test --filter "<regex>"`
- Generate coverage: `acton test --coverage --format lcov`
- Run mutation tests: `acton test --mutate --mutate-contract <contract-id>`
- Start debugger: `acton test --debug --debug-port 8080`

## Deploy through scripts

- Do not use a nonexistent `acton deploy` command.
- Run deployment logic locally first:

```bash
acton script scripts/deploy.tolk
```

- Broadcast after successful local run:

```bash
acton script scripts/deploy.tolk --broadcast --net testnet
```

- Add `--api-key` for TonCenter-heavy operations when rate-limited.

## Manage wallets with secure defaults

- Create wallet:

```bash
acton wallet new --name deployer --local
```

- Prefer secure keyring storage over plain mnemonics when available.
- Treat `wallets.toml` and `global.wallets.toml` as sensitive files.
- Prefer `mnemonic-env` for CI or automation contexts.

## Verify and manage libraries

- Verify deployed source:

```bash
acton verify <contract> --address <address> --net testnet
```

- Dry-run verification when requested:

```bash
acton verify <contract> --address <address> --dry-run
```

- Use `acton library publish|fetch|info|topup` for library lifecycle tasks.

## Respond with operational clarity

- Return exact commands to run next.
- State wallet and network assumptions explicitly.
- Warn once before any action that can spend real TON.
