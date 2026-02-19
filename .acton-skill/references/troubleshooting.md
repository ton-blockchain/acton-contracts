# Troubleshooting

Use these checks before deeper debugging.

## Command not found

- Run `acton --version`.
- If missing, install via project installer script:
  - `curl -fsSL https://raw.githubusercontent.com/i582/acton/main/install.sh | bash`
- Ensure Acton binary directory is in `PATH`.

## Build fails

- Run `acton build --clear-cache`.
- Confirm every `[contracts.*]` entry in `Acton.toml` has correct `src` path.
- Confirm dependency names in `depends` match existing contract keys.
- Re-run a targeted build: `acton build <contract-id>`.

## Import or mapping resolution errors

- Confirm `[mappings]` entries in `Acton.toml` resolve relative to project root.
- Verify import prefixes match mapping keys (for example `@core/...`).
- Avoid ambiguous relative imports when a mapping exists.

## Test failures that differ from local script behavior

- Run `acton test --filter "<specific-test>" --backtrace full`.
- Check whether script/test uses broadcast, fork-net, or local emulation.
- Verify fixtures and wrappers under `tests/` are up to date.

## Broadcast or wallet errors

- Run `acton wallet list --balance`.
- Confirm selected wallet exists in `wallets.toml` or global wallets.
- Confirm mnemonic source (`mnemonic-keyring`, `mnemonic-env`, `mnemonic-file`, or plain mnemonic) is accessible.
- Verify `--net` target matches funded wallet network.

## TonCenter rate limits or slow operations

- Retry with `--api-key <KEY>` on `script`, `verify`, or `wallet list --balance`.
- Prefer testnet during development loops.

## Verification mismatch

- Rebuild local sources with `acton build --clear-cache`.
- Confirm deployed address corresponds to the same source revision.
- Pass the original compiler version if known:
  - `acton verify <contract> --address <addr> --compiler-version <version>`

## Missing deploy command confusion

- Use `acton script scripts/deploy.tolk [--broadcast ...]`.
- Acton deployment is script-driven by design; there is no `acton deploy` command.
