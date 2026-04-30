# Elector

Original FunC: [ton-blockchain/ton: `elector-code.fc`](https://github.com/ton-blockchain/ton/blob/master/crypto/smartcont/elector-code.fc).

This package implements the validator election contract, covering stake intake, election lifecycle, validator-set updates, reward recovery, and complaint handling. Tests exercise stake entry and recovery, election announcement and execution, complaints and voting, validator-set confirmation and update, upgrade flow, and benchmarked happy paths.

Scripts in `scripts/` provide operational entry points for deployment, state inspection, election announcement, basic transfers, and stake recovery: `deploy.tolk`, `info.tolk`, `announce-elections.tolk`, `simple-transfer.tolk`, and `recover-stake.tolk`. Run them with `acton script elector/scripts/<name>.tolk` (add `--net testnet` to broadcast). Each prompt accepts an `ELECTOR_*` environment variable for non-interactive use; `info.tolk` defaults to the well-known elector address `-1:333…333`. `announce-elections.tolk` triggers `onRunTickTock` via the local emulator and is skipped in broadcast mode because tick-tock cannot be initiated externally.
