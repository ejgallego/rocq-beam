/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import RocqBeam.Broker.Protocol
import RocqBeam.Cli.Args
import RocqBeam.Path
import RocqBeam.Project
import RocqBeam.System

open Lean

namespace RocqBeam.Cli

open RocqBeam.Broker

partial def climbParents (path : System.FilePath) (count : Nat) : System.FilePath :=
  match count with
  | 0 => path
  | n + 1 => climbParents (path.parent.getD path) n

def beamHome : IO System.FilePath := do
  match ← IO.getEnv "ROCQ_BEAM_HOME" with
  | some root => RocqBeam.resolveExistingPath <| System.FilePath.mk root
  | none => RocqBeam.resolveExistingPath <| climbParents (← IO.appPath) 4

partial def findRootUpwards (start : System.FilePath) : IO (Option System.FilePath) := do
  let dir ← RocqBeam.resolveExistingPath start
  if ← RocqBeam.Project.hasRocqProject dir then return some dir
  let parent := dir.parent.getD dir
  if parent == dir then return none
  findRootUpwards parent

def projectRootAny (opts : CliOptions) : IO System.FilePath := do
  match opts.explicitRoot? with
  | some root => RocqBeam.resolveExistingPath root
  | none =>
      match ← findRootUpwards (System.FilePath.mk ".") with
      | some root => pure root
      | none => throw <| IO.userError "could not infer Rocq project root; use --root PATH"

def projectRoot (opts : CliOptions) (_backend : Backend) : IO System.FilePath :=
  projectRootAny opts

def explicitProjectRoot (opts : CliOptions) (action : String) : IO System.FilePath := do
  match opts.explicitRoot? with
  | some root => RocqBeam.resolveExistingPath root
  | none => throw <| IO.userError s!"{action} requires an explicit --root PATH"

def maybeRocqCmd (root : System.FilePath) : IO (Option String) := do
  if let some cmd ← IO.getEnv "ROCQ_BEAM_COQ_LSP" then return some cmd
  for candidate in [root / "_opam" / "bin" / "coq-lsp", root / "_opam" / "_opam" / "bin" / "coq-lsp"] do
    if ← candidate.pathExists then return some candidate.toString
  if ← RocqBeam.commandAvailable "coq-lsp" then return some "coq-lsp"
  pure none

def rocqCmd (root : System.FilePath) : IO String := do
  match ← maybeRocqCmd root with
  | some command => pure command
  | none => throw <| IO.userError s!"could not find coq-lsp for {root}"

def defaultDaemonPath (home : System.FilePath) : IO System.FilePath := do
  let installed := home / "libexec" / "rocq-beam-daemon"
  if ← installed.pathExists then return installed
  pure <| home / ".lake" / "build" / "bin" / "rocq-beam-daemon"

def ensureDefaultDaemon (home : System.FilePath) : IO System.FilePath := do
  let daemon ← defaultDaemonPath home
  unless ← daemon.pathExists do
    let out ← IO.Process.output {
      cmd := "lake"
      args := #["build", "rocq-beam-daemon"]
      cwd := home.toString
    }
    unless out.exitCode == 0 do
      throw <| IO.userError s!"failed to build Rocq Beam daemon\n{out.stderr}"
    unless ← daemon.pathExists do
      throw <| IO.userError s!"missing Rocq Beam daemon after build: {daemon}"
  pure daemon

end RocqBeam.Cli
