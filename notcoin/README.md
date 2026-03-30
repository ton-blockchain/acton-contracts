# Notcoin

Original FunC: [OpenBuilders/notcoin-contract](https://github.com/OpenBuilders/notcoin-contract).

This package implements the Notcoin-oriented jetton stack with minter and wallet contracts, preserving the operational model of the original implementation. Tests cover admin and governance controls, bounce handling, gas profile, protocol validation, and wallet behavior.

Scripts in `scripts/` cover deployment, state inspection, minting, transfers, and admin or metadata updates via `deploy.tolk`, `info.tolk`, `mint.tolk`, `transfer.tolk`, `change-admin.tolk`, `claim-admin.tolk`, and `change-metadata.tolk`. Run them with `acton script notcoin/scripts/<name>.tolk`.
