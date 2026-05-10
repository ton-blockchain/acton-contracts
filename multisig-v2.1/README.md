# Multisig V2

Original FunC: [ton-blockchain/multisig-contract-v2](https://github.com/ton-blockchain/multisig-contract-v2).

This package implements the threshold multisig wallet and its dedicated order contracts for proposal execution, sequencing, and fee-aware lifecycle control. Tests exercise core multisig behavior, seqno modes, order lifecycle helpers, fee constants and cost paths, additional invariants, and end-to-end execution paths.

Scripts in `scripts/` provide operational entry points for deployment, state inspection, order creation, and multisig parameter updates: `deploy.tolk`, `info.tolk`, `new-order.tolk`, and `update-params.tolk`. Run them with `acton script multisig-v2/scripts/<name>.tolk`.
