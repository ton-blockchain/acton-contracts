# Counter

This suite has no original FunC counterpart; it is a native Tolk example for exercising the Acton toolchain.

It provides a minimal stateful counter contract for demonstrating build, test, wrapper, and deployment flows. Tests exercise the increment and read paths in a focused suite.

Scripts in `scripts/` provide operational entry points for deployment, state inspection, and basic counter actions: `deploy.tolk`, `info.tolk`, `increase.tolk`, and `reset.tolk`. Run them with `acton script counter/scripts/<name>.tolk`.
