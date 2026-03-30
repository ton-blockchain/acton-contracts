# Multisig V2

Original FunC: [ton-blockchain/multisig-contract-v2](https://github.com/ton-blockchain/multisig-contract-v2).

This package implements the threshold multisig wallet and its dedicated order contracts for proposal execution, sequencing, and fee-aware order lifecycle management. Tests cover multisig core behavior, seqno modes, order lifecycle and helpers, fee constants and costs, additional invariants, and end-to-end paths.

Scripts in `scripts/` cover deployment, state inspection, order creation, and multisig parameter updates via `deploy.tolk`, `info.tolk`, `new-order.tolk`, and `update-params.tolk`. Run them with `acton script multisig-v2/scripts/<name>.tolk`.
