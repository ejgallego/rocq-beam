/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import RocqBeam.Cli.Args
import RocqBeam.Cli.Commands
import RocqBeam.Cli.Project

namespace RocqBeam.Cli

def main (args : List String) : IO Unit := do
  let home ← beamHome
  let opts ← parseCliOptions {} args
  runCommand home opts

end RocqBeam.Cli

def main := RocqBeam.Cli.main
