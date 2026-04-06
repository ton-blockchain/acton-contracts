# DNS

Original FunC: [ton-blockchain/dns-contract](https://github.com/ton-blockchain/dns-contract).

This package implements the TON DNS stack, including root resolution, NFT-style collection and item ownership, and auction-based domain allocation. Tests cover root and collection behavior, item management, auction flow, DNS utility units, and end-to-end paths.

Scripts in `scripts/` are written as standalone operational scripts:

- `deploy-root.tolk` deploys the root resolver
- `deploy-dns.tolk` deploys the DNS collection
- `info.tolk` inspects existing root, collection, or item addresses
- `manage.tolk` updates an existing item's `dns_name`, wallet record, or owner

Run them with `acton script dns/scripts/<name>.tolk`.
