# Elector

Original FunC: [ton-blockchain/ton: `elector-code.fc`](https://github.com/ton-blockchain/ton/blob/master/crypto/smartcont/elector-code.fc).

This package implements the validator election contract, covering stake intake, election lifecycle, validator-set updates, reward recovery, and complaint handling. Tests exercise stake entry and recovery, election announcement and execution, complaints and voting, validator-set confirmation and update, upgrade flow, and benchmarked happy paths.

Scripts in `scripts/` provide operational entry points for deployment, state inspection, election announcement, and basic transfers: `deploy.tolk`, `info.tolk`, `announce-elections.tolk`, and `simple-transfer.tolk`. Run them with `acton script elector/scripts/<name>.tolk`.
