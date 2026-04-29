# Notcoin

Original FunC: [OpenBuilders/notcoin-contract](https://github.com/OpenBuilders/notcoin-contract).

Related TEPs: [TEP-74 Fungible tokens (Jettons) standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md), [TEP-89 Discoverable Jettons Wallets](https://github.com/ton-blockchain/TEPs/blob/master/text/0089-jetton-wallet-discovery.md), and [TEP-64 Token Data Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0064-token-data-standard.md).

This package implements the Notcoin-oriented jetton stack with minter and wallet contracts, preserving the operational model of the original implementation. Tests cover admin and governance controls, bounce handling, gas profile, protocol validation, and wallet behavior.

Scripts in `scripts/` cover deployment, state inspection, minting, transfers, and admin or metadata updates via `deploy.tolk`, `info.tolk`, `mint.tolk`, `transfer.tolk`, `change-admin.tolk`, `claim-admin.tolk`, and `change-metadata.tolk`. Run them with `acton script notcoin/scripts/<name>.tolk`.
