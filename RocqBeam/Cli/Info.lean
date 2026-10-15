/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import RocqBeam.Cli.DaemonManager
import RocqBeam.Cli.Output
import RocqBeam.Cli.Project
import RocqBeam.Daemon.Debug
import RocqBeam.Daemon.Paths

open Lean

namespace RocqBeam.Cli

open RocqBeam.Broker

def doctor (home : System.FilePath) (opts : CliOptions) (_backend : Backend) : IO Unit := do
  let root ← projectRootAny opts
  IO.println s!"rocq-beam home: {home}"
  IO.println s!"project root: {root}"
  IO.println s!"coq-lsp: {(← maybeRocqCmd root).getD "<missing>"}"
  IO.println s!"daemon binary: {← defaultDaemonPath home}"
  IO.println s!"registry: {← RocqBeam.Daemon.registryPathFor root opts.explicitControlDir?}"

end RocqBeam.Cli
