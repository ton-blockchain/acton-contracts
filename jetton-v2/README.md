# Jetton v2

Original FunC: [jetton-2.0 branch](https://github.com/ton-blockchain/jetton-contract/tree/jetton-2.0), [`jetton-minter.fc`](https://github.com/ton-blockchain/jetton-contract/blob/jetton-2.0/contracts/jetton-minter.fc), and [`jetton-wallet.fc`](https://github.com/ton-blockchain/jetton-contract/blob/jetton-2.0/contracts/jetton-wallet.fc).

This package ports the official Jetton v2 minter and wallet design to Tolk for the Acton workflow, with explicit storage, sharding, fee management, and protocol message types. Tests cover admin and governance controls, bounce handling, gas profile, protocol validation, state init, and wallet behavior.

Scripts in `scripts/` cover deployment, state inspection, minting, transfers, and admin or metadata updates via `deploy.tolk`, `info.tolk`, `mint.tolk`, `transfer.tolk`, `change-admin.tolk`, `claim-admin.tolk`, and `change-metadata.tolk`. Run them with `acton script jetton-v2/scripts/<name>.tolk`.
