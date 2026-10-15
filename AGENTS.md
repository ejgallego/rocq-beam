# AGENTS.md

This repository owns Rocq Beam. Keep the public surface limited to isolated saved-file goal probes
through `coq-lsp`. Use no fallback executor. Keep the `rocq-beam` skill Rocq-only and self-contained;
do not introduce shared Lean/Rocq skill files or dependencies on a Lean Beam checkout.

The implementation is Lean, preserved from the initial extraction. Generic broker infrastructure
is copied and owned here. Favor behavior-preserving changes and typed errors across asynchronous
boundaries. Do not add compatibility aliases for Lean Beam commands or environment variables.

Build with `lake build`. Run `bash tests/test-rocq-beam.sh` for broker or wrapper changes and
`bash tests/test-install.sh` for installer changes. Test with the pinned Rocq/coq-lsp dependencies
in `tests/rocq-ci.opam`. Never run an installer against real agent homes for validation.

If a file is open in the broker, do not edit it out of band. If coq-lsp reports unexpected stale or
rebuild trouble, stop and surface it. Do not edit the installed skill or Lean Beam's state as part
of normal tests. Keep destructive cleanup scoped to test-owned temporary directories.
