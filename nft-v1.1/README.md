# NFT

Original FunC: [ton-blockchain/nft-contract](https://github.com/ton-blockchain/nft-contract).

Related TEPs: [TEP-62 NFT Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0062-nft-standard.md), [TEP-64 Token Data Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0064-token-data-standard.md), and [TEP-66 NFT Royalty Standard Extension](https://github.com/ton-blockchain/TEPs/blob/master/text/0066-nft-royalty-standard.md).

This package implements the reference NFT collection and item contracts, including royalty queries, ownership transfers, and metadata flows. Tests exercise collection and item behavior, the full deployment and transfer flow, batch limits, initialization, and transfer fee boundaries.

Run these commands from the repository root:

```bash
acton build NftCollection
acton test nft-v1.1/tests
```

Scripts in `scripts/` provide deployment and collection or item management:

- `deployCollection.tolk` deploys a collection with on-chain metadata and royalty parameters.
- `deployItem.tolk` mints an item into an existing collection.
- `deployBatch.tolk` mints 1–249 items in a single transaction.
- `transferItem.tolk` transfers an item to a new owner.
- `changeAdmin.tolk` changes the collection admin.

Run them with `acton script nft-v1.1/scripts/<name>.tolk`. Without `--net`, scripts run in local emulation. Set `NFT_DEPLOYER` to a wallet name to skip the wallet prompt; otherwise, the scripts prompt for a wallet. Metadata and collection/item addresses are prompted separately.

Regenerate the Tolk wrappers after ABI changes:

```bash
acton wrapper NftCollection -o nft-v1.1/wrappers/NftCollection.gen.tolk
acton wrapper NftItem -o nft-v1.1/wrappers/NftItem.gen.tolk
```
