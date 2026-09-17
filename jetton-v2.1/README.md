# Jetton v2.1

Original FunC: [jetton-2.0 branch](https://github.com/ton-blockchain/jetton-contract/tree/jetton-2.0), [`jetton-minter.fc`](https://github.com/ton-blockchain/jetton-contract/blob/jetton-2.0/contracts/jetton-minter.fc), and [`jetton-wallet.fc`](https://github.com/ton-blockchain/jetton-contract/blob/jetton-2.0/contracts/jetton-wallet.fc).

Related TEPs: [TEP-74 Jetton Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md), [TEP-89 Jetton Wallet Discovery](https://github.com/ton-blockchain/TEPs/blob/master/text/0089-jetton-wallet-discovery.md), and [TEP-64 Token Data Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0064-token-data-standard.md).

This package ports the official Jetton v2 minter and wallet design to Tolk for the Acton workflow, with explicit storage, sharding, fee management, and protocol message types. Tests exercise admin and governance controls, bounce handling, gas profiling, protocol validation, `StateInit` handling, wallet behavior, complete token lifecycles, and mutation regressions.

Scripts in `scripts/` provide operational entry points for deployment, state inspection, minting, transfers, and admin or metadata updates: `deploy.tolk`, `info.tolk`, `mint.tolk`, `transfer.tolk`, `change-admin.tolk`, `claim-admin.tolk`, and `change-metadata.tolk`. Run them with `acton script jetton-v2.1/scripts/<name>.tolk`.


## Build and test

Run from the repository root:

```bash
acton build JettonMinter
acton test jetton-v2.1/tests
```

The minter build also compiles its wallet dependency. Regenerate wrappers after
changing the contract ABI:

```bash
acton wrapper JettonMinter -o jetton-v2.1/wrappers/JettonMinter.gen.tolk
acton wrapper JettonWallet -o jetton-v2.1/wrappers/JettonWallet.gen.tolk
```

`wrappers/utils.tolk` includes workchain-aware deployment, minting, and transfer
helpers. Transfers support explicit inline or reference payload encoding, or
automatic selection based on the available message-body space.

## Scripts

Start with an emulated deployment:

```bash
acton script jetton-v2.1/scripts/deploy.tolk
```

Deployment always starts with `totalSupply = 0`. Use `mint.tolk` to issue tokens
to a recipient; `JETTON_INITIAL_SUPPLY` is no longer used.

Scripts prompt for wallets, addresses, and metadata. For non-interactive use,
set their `JETTON_*` variables in a local `.env` or your shell. Deployment reads
`JETTON_DEPLOYER` and `JETTON_ADMIN_ADDRESS`; management scripts use
`JETTON_MINTER_ADDRESS` plus the relevant wallet, recipient, and amount.
Metadata defaults can be overridden with `JETTON_NAME`, `JETTON_SYMBOL`,
`JETTON_DESCRIPTION`, `JETTON_IMAGE`, and `JETTON_DECIMALS`.

After checking the emulation output, append `--net testnet` to broadcast a script
to testnet. Minting and transfers wait for the full transaction trace before
reporting the resulting balances.
