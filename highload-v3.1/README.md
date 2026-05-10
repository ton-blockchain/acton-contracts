# Highload V3

Original FunC: [ton-blockchain/highload-wallet-contract-v3](https://github.com/ton-blockchain/highload-wallet-contract-v3).

This package implements the high-throughput wallet optimized for batched dispatch, replay protection, and bounded query-state management. Tests exercise validation, batching and action dispatch, internal filters, replay-timeout handling, storage and query cleanup limits, and end-to-end flows.

Scripts in `scripts/` provide operational entry points for deployment, state inspection, and transfer submission: `deploy.tolk`, `info.tolk`, and `send-transfer.tolk`. Run them with `acton script highload-v3/scripts/<name>.tolk`.
