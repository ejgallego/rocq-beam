# Rocq Beam

Inspect saved Rocq proof states and speculative tactic prefixes through `coq-lsp`, from an agent or
shell.

**Status: feature-complete and frozen.** The current goal-inspection workflow is complete; no
further feature development is planned.

Rocq Beam is an independent project extracted from Lean Beam. Its implementation is Lean, with the
build toolchain pinned in [lean-toolchain](lean-toolchain). Target Rocq projects need no Lean
configuration, plugin, or Lean Beam installation.

## Install

With `elan` available on `PATH`:

```sh
git clone https://github.com/ejgallego/rocq-beam.git
cd rocq-beam
./scripts/install-rocq-beam.sh --codex
```

The installer builds the tool, places `rocq-beam` in `~/.local/bin`, and copies its runtime binaries
to `~/.local/share/rocq-beam/libexec`. Make sure `~/.local/bin` is on `PATH`.
`--prefix DIR` selects another absolute installation prefix.

`--codex` also installs the Rocq agent skill. Use `--claude`, `--pi`, `--opencode`, or `--vibe` for
another agent, or `--all-skills` for all five. Omit these flags to install only the command-line tool.
Restart active agent sessions after installing the skill.

Install `coq-lsp` separately for your Rocq project. Rocq Beam resolves it from
`ROCQ_BEAM_COQ_LSP`, then the project's local `_opam/bin`, then `PATH`. Set
`ROCQ_BEAM_COQ_LSP` to an explicit executable when needed.

## Use

Keep a foreground session running in one terminal:

```sh
rocq-beam --root /path/to/project serve
```

Probe saved `.v` files from another terminal, using the filenames and positions in your project:

```sh
rocq-beam --root /path/to/project goals-after Demo.v 2 8
rocq-beam --root /path/to/project goals-prev Semi.v 2 3 'split.'
rocq-beam --root /path/to/project open-files
rocq-beam --root /path/to/project stats
rocq-beam --root /path/to/project stop
```

Positions are zero-based LSP lines and UTF-16 character coordinates. `goals-after` inspects the
state after an existing sentence. `goals-prev` selects the preceding state and accepts optional
speculative sentence text. A probe does not edit the file, and speculative text does not become
the basis of the next probe. Save files before probing; stop the session before editing an open
file, then save and restart it.

Ordinary commands attach to the running session and never start one implicitly. Without `--root`,
they find the nearest `_RocqProject` or `_CoqProject` in the current directory or its ancestors.
`stop` and `recover` always require an explicit root. Interrupting `serve` also stops its session.

Goal probes, session commands, `open-files`, and `stats` emit JSON on stdout. `doctor` and `version`
print text. Check exit status: setup and transport failures may emit only stderr. Use
`rocq-beam --help` for the command list.

The session descriptor is `<root>/.rocq-beam/rocq-beam-daemon.json`. For an alternate location, set
`ROCQ_BEAM_SESSION_ROOT` to a writable absolute directory, or pass the same absolute
`--session-dir DIR` to the owner and every attaching command. Inspect `status` after a crash;
`recover --generation ID` quarantines that session's descriptor, while `recover --force` handles an
invalid descriptor. Recovery does not signal saved PIDs.

The scope is goal inspection through `coq-lsp`. There is no source-editing, `run-at`, sync/checkpoint,
continuation-handle, or MCP interface. If `coq-lsp` reports unexpected stale or broken state, stop
and report it; retry from a freshly saved file and session.

## Dependencies and checks

The CI dependency set is Rocq 9.1.1 and coq-lsp 0.2.5+9.1, declared in
[tests/rocq-ci.opam](tests/rocq-ci.opam). To install this set for the repository's fixtures and tests,
select an active opam switch, then run:

```sh
bash tests/setup-rocq-opam.sh
bash tests/test-rocq-beam.sh
bash tests/test-install.sh
```

The setup script adds the Rocq opam repository, updates package metadata, and installs the pinned
dependencies into the active switch. The test scripts cover wrapper sessions, saved-file and
speculative goals, request isolation, backend errors, and installation in fake agent homes.
The CI workflow runs them on Linux and macOS.

See [SOURCE_ORIGIN.md](SOURCE_ORIGIN.md) for provenance, retained internal runtime code, and license
information.
