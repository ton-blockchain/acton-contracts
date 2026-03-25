# Troubleshooting

Use these checks before deeper debugging.

## Docs and source disagree

- Treat current source and checked-in docs as authoritative over hosted mirrors.
- Verify command names and defaults in:
  - `src/bin/acton.rs`
  - `src/commands/**`
  - `crates/acton-config/src/config.rs`
- Known mismatches in this checkout:
  - no current `acton hooks` command even if some hosted docs mention it
  - use `acton up --canary`, not older `--trunk`
  - use `acton test --coverage-format`, not older `--format`

## Project root or manifest confusion

- Run `acton doctor`.
- Check `pwd`.
- Re-run with explicit project selection:
  - `acton --project-root /abs/path ...`
  - `acton --manifest-path /abs/path/Acton.toml ...`
- Remember: project-root controls relative outputs like `.acton`, `wallets.toml`, `test-results`, and traces.

## Build or import resolution failures

- Run `acton build --clear-cache`.
- Confirm every `[contracts.*]` entry in `Acton.toml` has a valid `src`.
- Confirm dependency names in `depends` match real contract keys.
- Inspect `[mappings]` and resolve imports relative to project root.
- If the project was added manually, run `acton init` to patch default mappings and `.gitignore`.

## Wrapper generation problems

- Confirm the contract is declared in `Acton.toml`; `acton wrapper` takes a contract id, not a file path.
- Confirm the contract compiles cleanly with `acton build <contract-id>`.
- If wrapper methods are missing, inspect the contract header:
  - `storage: ...`
  - `incomingMessages: ...`
- If `acton wrapper --ts` fails, verify Node.js, npm, and `npx` are installed.
- Do not combine `--ts` with `--test`, `--test-output`, or `--test-output-dir`.

## Test behavior differs from scripts

- Re-run a focused case:
  - `acton test --filter "<specific-test>" --backtrace full`
- Check whether the script or test is using:
  - `--broadcast`
  - `--fork-net`
  - `--show-bodies`
  - local emulation vs remote state
- If ABI changed, regenerate wrappers instead of debugging old generated code.

## Test UI will not start

- Selected port may already be busy; retry with `acton test --ui --ui-port 23456`.
- If the test run itself fails before UI bootstrap, run without `--ui` first to isolate compile/runtime errors.

## Coverage, profiling, or reporter confusion

- Prefer current source spellings:
  - `--coverage-format lcov`
  - `--coverage-file <path>`
  - `--reporter console|dot|teamcity|junit`
- For gas regressions:
  - create baseline with `acton test --snapshot gas-baseline.json`
  - compare with `acton test --baseline-snapshot gas-baseline.json`
  - enforce in CI with `--fail-on-diff`

## Wallet, faucet, or broadcast issues

- Run `acton wallet list --balance`.
- Confirm the selected wallet exists in local or global config.
- Confirm the mnemonic source is available:
  - `mnemonic-env`
  - `mnemonic-file`
  - `mnemonic-keyring`
  - `mnemonic`
- Confirm expected addresses match the target network.
- Verify `--net` matches the funded wallet environment.
- Use `mnemonic-env` for CI instead of plaintext secrets.

## TonCenter rate limits or slow network operations

- Retry with `--api-key <KEY>` or set `TONCENTER_API_KEY`.
- This commonly affects:
  - `acton script --broadcast`
  - `acton verify`
  - `acton wallet list --balance`
  - `acton test --fork-net ...`
  - `acton disasm --address ...`
  - `acton retrace ...`

## LiteNode and localnet issues

- If localnet commands fail, verify the node is actually running:
  - `acton litenode start`
- If port assumptions are unclear, verify current defaults from source or pass `--port` explicitly.
- `--load-state` and `--db-path` cannot be used together.
- If startup wallets fail, confirm `[litenode].accounts` names resolve to real wallets.
- For script deploys, remember localnet broadcasting expects the local node to be running:
  - `acton script scripts/deploy.tolk --broadcast --net localnet`

## Verification mismatch

- Rebuild locally with `acton build --clear-cache`.
- Confirm the deployed address matches the source revision you are using.
- Pass the compiler version if needed:
  - `acton verify <contract> --address <addr> --compiler-version <version>`
- Use `--dry-run` first when verifying unfamiliar deployments.

## Disasm or retrace problems

- For live-chain reads, provide `--api-key` if rate limits bite.
- For readable disassembly, regenerate source maps:
  - `acton compile contract.tolk --source-map contract.json --boc contract.boc`
  - `acton disasm contract.boc --source-map contract.json --show-offsets`

## `func2tolk` or LSP failures

- `acton func2tolk` requires `npx`; install Node.js/npm if missing.
- `acton ls` expects `.acton/tolk-stdlib` to exist; run `acton init` or `acton build` if the stdlib is missing.

## Missing deploy command confusion

- Use `acton script scripts/deploy.tolk [--broadcast ...]`.
- Acton deployment is script-driven by design; there is no `acton deploy` command.
