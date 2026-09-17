# Counter

This suite has no original FunC counterpart; it is a native Tolk example for exercising the Acton toolchain.

It provides a counter whose owner can increment, decrement, and reset its value. Tests cover owner checks, updates, underflow, and invalid messages.

Scripts in `scripts/` provide deployment, state inspection, and counter actions: `deploy.tolk`, `info.tolk`, `increase.tolk`, and `reset.tolk`. Run them with `acton script counter/scripts/<name>.tolk`.

The `deployer` wallet becomes the owner of a new counter. Scripts accept `COUNTER_ADDRESS` to target an existing contract, `COUNTER_DEPLOY_VALUE_NANOS` to set the deployment value (default: 5000000), and `COUNTER_DELTA` to set the increment (default: 1). Without an explicit address, scripts deploy the counter when needed.
