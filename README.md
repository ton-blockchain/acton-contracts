# Acton Contracts

Reference-grade TON contracts in Tolk, built with the Acton toolchain.

This monorepo collects reference implementations for main TON ecosystem contracts, build with modern Tolk + Acton stack. Each contract system is kept interface-compatible with its original FunC version. Where it was possible, Tolk BoCs were tested against existing Typescript Sandbox tests.

## Included

- Protocol contracts: [`config`](./config/), [`elector`](./elector/), [`dns`](./dns/)
- Wallets: [`w5`](./w5/), [`highload-v3`](./highload-v3/), [`multisig-v2`](./multisig-v2/)
- Tokens and assets: [`nft`](./nft/), [`jetton-v2`](./jetton-v2/), [`notcoin`](./notcoin/)
- Minimal example: [`counter`](./counter/)

Each suite is organized as a self-contained package with `contracts/`, `tests/`, and, where needed, `scripts/`. Selected suites also carry benchmark baselines for regression tracking.

## Workflow

```bash
acton build
acton test
acton check
acton fmt --check
```

Run a single suite:

```bash
acton test dns/tests
acton test elector/tests
acton test multisig-v2/tests
```

Run a benchmark comparison against the checked-in DNS baseline:

```bash
acton test dns/tests/e2e_happy_paths.test.tolk --baseline-snapshot dns/tests/benchmarks/v1.json --fail-on-diff
```

Refresh the DNS benchmark snapshot:

```bash
acton test dns/tests/e2e_happy_paths.test.tolk --snapshot dns/tests/benchmarks/v1.json
```

Run a deployment script:

```bash
acton script dns/scripts/deploy.tolk
acton script w5/scripts/deploy.tolk
```

CI executes the same build, test, lint, and format pipeline on every change.
