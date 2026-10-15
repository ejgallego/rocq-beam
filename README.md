# Rocq Beam

Rocq Beam gives agents saved-file proof-state inspection through `coq-lsp`. It is an independent
project extracted from Lean Beam, with its own executable, runtime, session directory, and agent
skill. It does not depend on a Lean Beam checkout or installation.

The first version preserves the existing Lean implementation of the broker. Lean and Lake are
build dependencies for the tool itself; target Rocq projects need no Lean configuration or plugin.

## Build and install

Install `elan`, then build the pinned toolchain and executables:

```sh
lake build
./scripts/install-rocq-beam.sh --codex
```

The installer places `rocq-beam` in `~/.local/bin` and its two runtime binaries in
`~/.local/share/rocq-beam/libexec`. `--prefix DIR` selects another absolute installation prefix.
The optional `--codex`, `--claude`, `--pi`, `--opencode`, and `--vibe` flags install only the Rocq
skill for that agent; `--all-skills` selects all five. Restart active agent sessions afterward.
Installation does not install or change `coq-lsp`.

## Rocq setup

Use `coq-lsp`; there is no fallback executor. Set `ROCQ_BEAM_COQ_LSP` to an explicit executable,
or install `coq-lsp` in the target project's `_opam/bin` or on `PATH`. An explicit environment
override takes precedence over the project's local switch.

The CI dependency set is Rocq 9.1.1 and coq-lsp 0.2.5+9.1, declared in
[tests/rocq-ci.opam](tests/rocq-ci.opam). With an active opam switch, install it using:

```sh
bash tests/setup-rocq-opam.sh
```

## Use

Keep a foreground owner running in one terminal:

```sh
rocq-beam --root /path/to/project serve
```

Probe from another terminal:

```sh
rocq-beam --root /path/to/project doctor
rocq-beam --root /path/to/project goals-after Demo.v 2 8
rocq-beam --root /path/to/project goals-prev Semi.v 2 3 'split.'
rocq-beam --root /path/to/project open-files
rocq-beam --root /path/to/project stats
rocq-beam --root /path/to/project stop
```

Without `--root`, ordinary commands find the nearest `_RocqProject` or `_CoqProject` in the current
directory or its ancestors. `stop` and `recover` always require an explicit root.

Save `.v` files before probing. Positions are zero-based LSP line and UTF-16 character coordinates.
`goals-after` inspects the state after an existing sentence. `goals-prev` selects the preceding
state and accepts optional speculative sentence text. Every probe starts from the current saved
file; speculative text does not edit the document or become the basis of the next probe.
Successful requests emit one JSON response on stdout. Setup and transport failures may emit only
stderr and a nonzero exit status. Do not recover control flow by parsing exception text.

The session descriptor is `<root>/.rocq-beam/rocq-beam-daemon.json`. For a writable alternate
location, set `ROCQ_BEAM_SESSION_ROOT` or pass the same absolute `--session-dir DIR` to the owner
and all attaching commands. Ordinary commands attach and never start a session implicitly.
Interrupt the foreground owner or use `stop` when finished. A crash may require explicit
`recover --generation ID` (or `--force` for an invalid descriptor); recovery never signals a saved PID.
Rocq Beam does not use Lean Beam's `.beam` directory or `BEAM_*` environment variables.

There is no source-editing, `run-at`, sync/checkpoint, handle, or MCP interface. If `coq-lsp` reports
unexpected stale or broken state, stop and report it; retry only from a freshly saved file and session.

## Development

```sh
bash tests/test-rocq-beam.sh
bash tests/test-install.sh
```

`test-rocq-beam.sh` builds the executables, runs the transferred wrapper lifecycle test, checks
saved-file and speculative goals, and runs the transferred broker smoke test against real `coq-lsp`.
`test-install.sh` checks an isolated installation with fake agent homes.
CI runs these checks on Linux and macOS.

See [SOURCE_ORIGIN.md](SOURCE_ORIGIN.md) for extraction provenance and the retained runtime scope.
