# DNS

Original FunC: [ton-blockchain/dns-contract](https://github.com/ton-blockchain/dns-contract).

Related TEPs: [TEP-81 TON DNS Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0081-dns-standard.md), [TEP-62 NFT Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0062-nft-standard.md), and [TEP-64 Token Data Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0064-token-data-standard.md).

This package implements the TON DNS stack, including root resolution, NFT-style collection and item ownership, and auction-based domain allocation. Tests cover root and collection behavior, item management, auction flow, DNS utility units, and end-to-end paths.

Scripts in `scripts/` are written as standalone operational scripts:

- `deploy-root.tolk` deploys the root resolver
- `deploy-dns.tolk` deploys the DNS collection
- `info.tolk` inspects existing root, collection, or item addresses
- `manage.tolk` updates an existing item's `dns_name`, wallet record, or owner

Run them with `acton script dns/scripts/<name>.tolk`.
