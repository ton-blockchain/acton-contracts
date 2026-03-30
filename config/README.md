# Config

Original FunC: [ton-blockchain/ton: `config-with-ownable-params.fc`](https://github.com/ton-blockchain/ton/blob/master/crypto/smartcont/config-with-ownable-params.fc).

This package implements the governance-managed config contract responsible for proposing, voting on, and applying network parameter updates. Tests cover proposal creation, internal and external voting, special and custom params, validator-set and ticktock paths, and end-to-end governance flows.

Scripts in `scripts/` cover deployment, state inspection, and submitting config proposals via `deploy.tolk`, `info.tolk`, and `propose.tolk`. Run them with `acton script config/scripts/<name>.tolk`.
