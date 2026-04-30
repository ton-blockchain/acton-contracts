# W5

Original FunC: [ton-blockchain/wallet-contract-v5](https://github.com/ton-blockchain/wallet-contract-v5).

This package implements Wallet V5, including signed external execution, internal execution, extension support, and the get-method surface. Tests exercise external and internal message flows, extensions, get methods, and core wallet behavior.

Scripts in `scripts/` provide operational entry points for deployment, state inspection, transfer submission, and extension management: `deploy.tolk`, `info.tolk`, `send-transfer.tolk`, `add-extension.tolk`, `remove-extension.tolk`, and `set-signature.tolk`. Run them with `acton script w5/scripts/<name>.tolk`.
