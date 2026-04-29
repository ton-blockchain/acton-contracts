# NFT

Original FunC: [ton-blockchain/nft-contract](https://github.com/ton-blockchain/nft-contract).

Related TEPs: [TEP-62 NFT Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0062-nft-standard.md), [TEP-64 Token Data Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0064-token-data-standard.md), and [TEP-66 NFT Royalty Standard Extension](https://github.com/ton-blockchain/TEPs/blob/master/text/0066-nft-royalty-standard.md).

This package implements the reference NFT collection and item contracts, including royalty-aware transfer and metadata flows. Tests exercise collection and item behavior in focused reference suites.

Scripts in `scripts/` provide operational entry points for deployment, state inspection, and collection or item management: `deploy.tolk`, `info.tolk`, and `manage.tolk`. Run them with `acton script nft/scripts/<name>.tolk`.
