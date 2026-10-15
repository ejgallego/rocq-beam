# Source origin

Extracted from `leanprover/lean-beam` commit `2cfe347` under the Apache 2.0 license. Original
copyright and author notices are retained in copied source files.

This first split preserves the Lean broker implementation, including its request isolation,
document versions, cancellation, transport, bounded stderr capture, and foreground-owner lifecycle.
The copied runtime is maintained in this repository under the `RocqBeam` namespace. It has no
package dependency on Lean Beam and shares no installed runtime, session state, or skill helpers.

The retained broker implementation contains internal Lean-specific support types and helpers.
They are implementation scaffolding from the extraction, not supported Rocq operations. The Rocq
entry points reject Lean backends and restrict admission to session control, saved-file updates,
goal probes, and introspection. The installer ships only the Rocq CLI and daemon. Trimming the
copied internal scaffolding can be reviewed separately without changing the public Rocq surface.

The transferred `RocqSmokeTest` covers sentence goals, speculative prefixes, structured Rocq errors,
unsupported operations, and operation counters. The wrapper test preserves explicit ownership,
read-only doctor behavior, lazy source-daemon builds, and missing-owner recovery guidance.
