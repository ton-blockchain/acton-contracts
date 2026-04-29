# Jetton v2

Original FunC: [jetton-2.0 branch](https://github.com/ton-blockchain/jetton-contract/tree/jetton-2.0), [`jetton-minter.fc`](https://github.com/ton-blockchain/jetton-contract/blob/jetton-2.0/contracts/jetton-minter.fc), and [`jetton-wallet.fc`](https://github.com/ton-blockchain/jetton-contract/blob/jetton-2.0/contracts/jetton-wallet.fc).

Related TEPs: [TEP-74 Jetton Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md), [TEP-89 Jetton Wallet Discovery](https://github.com/ton-blockchain/TEPs/blob/master/text/0089-jetton-wallet-discovery.md), and [TEP-64 Token Data Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0064-token-data-standard.md).

This package ports the official Jetton v2 minter and wallet design to Tolk for the Acton workflow, with explicit storage, sharding, fee management, and protocol message types. Tests exercise admin and governance controls, bounce handling, gas profiling, protocol validation, `StateInit` handling, and wallet behavior.

Scripts in `scripts/` provide operational entry points for deployment, state inspection, minting, transfers, and admin or metadata updates: `deploy.tolk`, `info.tolk`, `mint.tolk`, `transfer.tolk`, `change-admin.tolk`, `claim-admin.tolk`, and `change-metadata.tolk`. Run them with `acton script jetton-v2/scripts/<name>.tolk`.
