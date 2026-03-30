# Counter

This suite has no original FunC counterpart; it is a native Tolk example used to exercise the Acton toolchain.

It provides a minimal stateful counter contract for demonstrating build, test, wrapper, and deployment flows. Tests cover the core increment and read behavior in a single focused suite.

Scripts in `scripts/` cover deployment, state inspection, and the basic counter actions via `deploy.tolk`, `info.tolk`, `increase.tolk`, and `reset.tolk`. Run them with `acton script counter/scripts/<name>.tolk`.
