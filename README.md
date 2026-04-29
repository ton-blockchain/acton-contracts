# Acton Contracts

Reference-grade TON contracts in Tolk, built with the [Acton toolchain](https://ton-blockchain.github.io/acton/).

This monorepo collects reference implementations for core TON ecosystem contracts, built on the modern Tolk and Acton stack. Each contract system preserves interface compatibility with its original FunC implementation. Where practical, compiled Tolk BoCs are validated against the existing TypeScript Sandbox test suites.

## Included

- Protocol contracts: [`config`](./config/), [`elector`](./elector/), [`dns`](./dns/)
- Wallets: [`w5`](./w5/), [`highload-v3`](./highload-v3/), [`multisig-v2`](./multisig-v2/)
- Tokens and assets: [`nft`](./nft/), [`jetton-v2`](./jetton-v2/), [`notcoin`](./notcoin/)
- Minimal example: [`counter`](./counter/)

Each suite is organized as a self-contained package with `contracts/`, `tests/`, and, where needed, `scripts/`. Selected suites also include benchmark baselines for regression tracking.

## Get started with Acton

[Acton](https://ton-blockchain.github.io/acton/) is a modern toolchain for TON smart contract development. It includes a native Tolk test runtime, an IDE-integrated debugger, dApp-ready templates, wallet management with testnet faucet support, and a scripting framework.

Install Acton:

```bash
curl -LsSf https://ton.org/acton/install.sh | sh
```

Learn more in the [Acton documentation](https://ton-blockchain.github.io/acton/docs/welcome).

## AI integrations

Acton and this monorepo are designed to work well with AI coding agents. Install the TON development skills:

```bash
npx skills add https://github.com/ton-blockchain/acton-contracts/tree/skills/skills
# Or for a specific agent
npx skills add https://github.com/ton-blockchain/acton-contracts/tree/skills/skills/acton -g -a claude-code -y
```

Then ask your agent to complete an engineering task in this project:

**Optimize multisig-v2 gas usage. Use $acton and $tolk skills. Make gas snapshots and run benchmarks for comparison between different versions. Your optimizations should pass all current tests.**


## Wrappers

All `WrapperName.gen.tolk` wrappers in this monorepo are generated automatically and used for Tolk testing and scripting.

To generate TypeScript wrappers:

```bash
acton wrapper --ts ContractName
```

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
acton test dns/tests/e2e-happy-paths.test.tolk --baseline-snapshot dns/tests/benchmarks/v1.json --fail-on-diff
```

Refresh the DNS benchmark snapshot:

```bash
acton test dns/tests/e2e-happy-paths.test.tolk --snapshot dns/tests/benchmarks/v1.json
```

Run a deployment script:

```bash
acton script dns/scripts/deploy.tolk
acton script w5/scripts/deploy.tolk
```

CI executes the same build, test, lint, and format pipeline on every change.
