# Acton Contracts Monorepo

Rewritten TON ecosystem contracts in **Tolk** with **Acton** build/test flows.

## Current Rewrite Status

### Implemented in this repo

1. [counter](/counter/contracts/counter.tolk) (example contract)

2. [notcoin](/notcoin/contracts/jetton-minter-contract.tolk) jetton stack

## Repository Layout

```text
.
├── Acton.toml
├── counter/
│   ├── contracts/
│   ├── tests/
│   └── scripts/
└── notcoin/
    ├── contracts/
    ├── tests/
    └── scripts/
```

## Run

```bash
# tests
acton run test-counter
acton run test-notcoin
# or
acton test counter/tests
acton test notcoin/tests

# deploy scripts
acton run counter/scripts/deploy.tolk
acton run notcoin/scripts/deploy.tolk
```

## TODO: Contracts to Implement in Tolk + Acton

Legend: `[ ]` planned, `(*)` stretch/if time.

### P0 - Core ecosystem parity

- [ ] Config contract rewrite
  - https://github.com/ton-blockchain/ton/blob/master/crypto/smartcont/config-with-ownable-params.fc
- [ ] Elector contract rewrite
  - https://github.com/ton-blockchain/ton/blob/master/crypto/smartcont/elector-code.fc
- [ ] Wallet V5
  - https://github.com/ton-blockchain/wallet-contract-v5
- [ ] Highload Wallet V3
  - https://github.com/ton-blockchain/highload-wallet-contract-v3
- [ ] Multisig V2
  - https://github.com/ton-blockchain/multisig-contract-v2
- [ ] DNS contract
  - https://github.com/ton-blockchain/dns-contract

### P1 - Token standards and modern token infra

- [ ] NFT reference contracts (collection + item + royalty-compatible flow)
  - https://github.com/ton-blockchain/nft-contract
  - TON Docs: https://docs.ton.org/standard/tokens/nft/reference
- [ ] SBT implementation (TEP-85 compliant)
  - https://github.com/ton-blockchain/TEPs/blob/master/text/0085-sbt-standard.md
  - TON Docs: https://docs.ton.org/standard/tokens/nft/sbt
- [ ] Jetton 2.0 branch parity (latest recommended jetton line)
  - https://github.com/ton-blockchain/jetton-contract/tree/jetton-2.0
  - TON Docs: https://docs.ton.org/standard/tokens/jettons/comparison
- [ ] Mintless jetton (large-scale airdrop pattern)
  - https://github.com/ton-community/mintless-jetton

### P2 - Wallet policy and treasury tooling (important additions from TON Docs)

- [ ] Lockup wallet
  - https://github.com/ton-blockchain/lockup-wallet-contract
  - TON Docs: https://docs.ton.org/standard/wallets/lockup
- [ ] Vesting contract
  - https://github.com/ton-blockchain/vesting-contract
  - TON Docs: https://docs.ton.org/standard/vesting
- [ ] Wallet V4 + subscription plugin (backward compatibility and plugin model)
  - https://github.com/ton-blockchain/wallet-contract
- [ ] Restricted wallet (community implementation, documented by TON Docs)
  - https://github.com/EmelyanenkoK/nomination-contract/tree/master/restricted-wallet
  - TON Docs: https://docs.ton.org/standard/wallets/restricted
- [ ] Preprocessed Wallet V2 (community, high efficiency)
  - https://github.com/pyAndr3w/ton-preprocessed-wallet-v2
  - TON Docs: https://docs.ton.org/standard/wallets/preprocessed-v2/specification

### P3 - Staking set (stretch)

- [ ] Liquid staking contract (*)
  - https://github.com/ton-blockchain/liquid-staking-contract
- [ ] Single nominator (*)
  - https://github.com/ton-blockchain/single-nominator
- [ ] Nominator pool (*)
  - https://github.com/ton-blockchain/nominator-pool

### Optional extras to evaluate later

- [ ] Locker contract (time-locked deposit/reward distribution)
  - https://github.com/ton-blockchain/locker-contract

## Notes

- Prioritize contracts with active ecosystem usage and clear spec coverage first (`P0`, `P1`).
- Keep compatibility test vectors for each rewrite against original FunC behavior.
- For community implementations (`restricted`, `preprocessed`, `mintless`), treat as separate tracks with stricter review/audit gates.
