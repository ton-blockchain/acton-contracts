# DNS

Original FunC: [ton-blockchain/dns-contract](https://github.com/ton-blockchain/dns-contract).

This package implements the TON DNS stack, including root resolution, NFT-style collection and item ownership, and auction-based domain allocation. Tests cover root and collection behavior, item management, auction flow, DNS utility units, and end-to-end paths.

Scripts in `scripts/` cover deployment, state inspection, and DNS management flows via `deploy.tolk`, `info.tolk`, and `manage.tolk`. Run them with `acton script dns/scripts/<name>.tolk`.
