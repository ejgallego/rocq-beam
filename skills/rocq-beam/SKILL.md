---
name: rocq-beam
description: Inspect saved Rocq proof states and speculative tactic prefixes through the independent rocq-beam wrapper and coq-lsp.
---

# Rocq Beam

Use the installed `rocq-beam` wrapper for Rocq proof-state inspection. Use only `coq-lsp`, with no
fallback executor. This skill is Rocq-only and self-contained.

## Setup

From the `rocq-beam` checkout, build with `lake build` and install with
`./scripts/install-rocq-beam.sh --codex`. Other supported targets are `--claude`, `--pi`,
`--opencode`, `--vibe`, and `--all-skills`. Restart agent sessions after installation.
Install coq-lsp in the target project's local `_opam/bin` or on `PATH`, or set
`ROCQ_BEAM_COQ_LSP` to its executable. The override takes precedence over the local switch.

## Workflow

Start one foreground owner and keep it running:

```sh
rocq-beam --root /absolute/project serve
```

Issue requests from another process:

```sh
rocq-beam --root /absolute/project goals-after Demo.v 2 8
rocq-beam --root /absolute/project goals-prev Semi.v 2 3 'split.'
rocq-beam --root /absolute/project open-files
rocq-beam --root /absolute/project stats
```

Save the file before each probe after a real edit. Positions use zero-based LSP lines and UTF-16
characters. Use `goals-after` by default. Use `goals-prev` with sentence text for intermediate
states inside a tactic sentence. Each request starts from the current saved file; it neither edits
the source nor mutates the basis of the next probe. Do not edit files out of band while they are
open in the broker. Stop the owner before making a real edit to an open file, then save and
restart the owner before probing again.

Commands attach to the selected owner; they do not start a daemon. Without `--root`, ordinary
commands find the nearest `_RocqProject` or `_CoqProject`. Prefer an explicit absolute root in agent
workflows. The descriptor lives at `<root>/.rocq-beam/rocq-beam-daemon.json`. In a read-only tree,
set `ROCQ_BEAM_SESSION_ROOT` to a writable absolute directory, or pass the same absolute
`--session-dir DIR` to every command. Startup or localhost TCP access may require sandbox approval.

Successful calls write a JSON response to stdout. Check exit status first; setup and transport
errors may write only stderr. Never parse exception text to recover structured control flow.
A failed speculative tactic exits nonzero with `ok: false`, `error.code`, and `error.message` in
the JSON response on stdout. Read that structured diagnostic and continue with another probe from
the saved source; an ordinary tactic failure does not require restarting the session.
If a file changes during a probe, rerun from the saved file. If coq-lsp reports unexpected stale or
broken state, stop and report it loudly.

Interrupt the owner or run `rocq-beam --root /absolute/project stop` when finished. For crash state,
inspect `status` and use explicit `recover --generation ID`, or `recover --force` for an invalid
descriptor. Recovery does not signal persisted PIDs.

There is no `run-at`, sync/checkpoint, continuation handle, source-editing, or MCP surface. Keep
pretty-printed goals as strings (`ppFormat = Str`, set by the wrapper). Do not use raw JSON or raw
LSP as the user workflow. Never assume hidden proof-session state persists between probes.
