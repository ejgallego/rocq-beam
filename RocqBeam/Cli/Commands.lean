/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import RocqBeam.Cli.Args
import RocqBeam.Cli.Broker
import RocqBeam.Cli.DaemonManager
import RocqBeam.Cli.Info
import RocqBeam.Cli.Project
import RocqBeam.Cli.Usage

open Lean

namespace RocqBeam.Cli

open RocqBeam.Broker

private inductive SessionState where
  | absent
  | running
  | stopping
  | recoveryRequired
  deriving BEq, Repr

private instance : ToJson SessionState where
  toJson
    | .absent => "absent"
    | .running => "running"
    | .stopping => "stopping"
    | .recoveryRequired => "recoveryRequired"

private structure SessionStatus where
  state : SessionState
  workspace : String
  sessionDir : String
  generation? : Option String := none
  detail? : Option String := none
  deriving ToJson

private structure SessionTransitionWarning where
  code : String
  message : String
  deriving ToJson

private structure SessionTransitionResult where
  state : SessionState
  changed : Bool
  warning? : Option SessionTransitionWarning := none
  deriving ToJson

private structure SessionRecoveryResult where
  state : SessionState
  changed : Bool
  generation? : Option String := none
  quarantinedPath? : Option String := none
  reason? : Option String := none
  deriving ToJson

private def mkSessionStatus
    (state : SessionState)
    (workspace sessionDir : System.FilePath)
    (generation? detail? : Option String := none) : SessionStatus := {
  state
  workspace := workspace.toString
  sessionDir := sessionDir.toString
  generation?
  detail?
}

private def updateVersionForRocqGoals
    (root : System.FilePath)
    (client : ProjectDaemonClient)
    (path : String) : IO Nat := do
  let resp ← requestBroker root client {
    payload := .updateFile { backend := .rocq, path }
  }
  match decodeUpdateFileResult resp with
  | .ok result => pure result.version
  | .error (.broker failure) => throw <| IO.userError failure.error.message
  | .error (.invalidPayload detail) =>
      throw <| IO.userError <|
        s!"update_file returned an invalid result while obtaining document version: {detail}"

private def stopProjectSession (opts : CliOptions) : IO Unit := do
  let root ← explicitProjectRoot opts "stop"
  match ← shutdownRegisteredProjectDaemon root opts.explicitControlDir? with
  | .absent =>
      printResponse <| Response.success <|
        toJson ({ state := .absent, changed := false } : SessionTransitionResult)
  | .alreadyStopping =>
      printResponse <| Response.success <| toJson ({
        state := .stopping
        changed := false
      } : SessionTransitionResult)
  | .stopping delivery =>
      let warning? ←
        match delivery with
        | .acknowledged => pure none
        | .rejected failure =>
            pure <| some ({
              code := "shutdownRejected"
              message := failure.error.message
            } : SessionTransitionWarning)
        | .failed failure =>
            pure <| some ({
              code := "shutdownDeliveryFailed"
              message := ← daemonFailureMessage root failure opts.explicitControlDir?
            } : SessionTransitionWarning)
      printResponse <| Response.success <| toJson ({
        state := .stopping
        changed := true
        warning?
      } : SessionTransitionResult)

private def recoverProjectSession (opts : CliOptions) (args : List String) : IO Unit := do
  let root ← explicitProjectRoot opts "recover"
  let (generation?, forceOpaque) ←
    match args with
    | ["--generation", generation] => pure (some generation, false)
    | ["--force"] => pure (none, true)
    | _ =>
        throw <| IO.userError
          "usage: rocq-beam --root PATH [--session-dir DIR] recover --generation ID | --force"
  let result ← recoverProjectDaemon root generation? forceOpaque opts.explicitControlDir?
  let result : SessionRecoveryResult :=
    match result with
    | .absent => {
        state := .absent
        changed := false
        reason? := some "absent"
      }
    | .recoveredGeneration generation quarantinedPath => {
        state := .absent
        changed := true
        generation? := some generation
        quarantinedPath? := some quarantinedPath.toString
      }
    | .recoveredOpaque quarantinedPath => {
        state := .absent
        changed := true
        quarantinedPath? := some quarantinedPath.toString
        reason? := some "opaque"
      }
  printResponse <| Response.success <| toJson result

private def runThenHoldUntilInterrupted
    (owner : ProjectDaemonOwner)
    (act : IO Unit) : IO Unit :=
  withInterruptWatcher fun watcher => do
    act
    while !(← watcher.interrupted) && (← owner.exitCode?).isNone &&
        (← owner.registered) && !(← IO.checkCanceled) do
      IO.sleep 50
    if ← watcher.interrupted then
      watcher.awaitInterrupt
    else if let some exitCode ← owner.exitCode? then
      unless exitCode == 0 do
        let tail := (← owner.stderrTail).trimAscii.toString
        let detail := if tail.isEmpty then "" else s!"\ndaemon stderr tail:\n{tail}"
        throw <| IO.userError s!"owned Beam daemon exited with status {exitCode}{detail}"

private def serveBackend
    (home : System.FilePath)
    (opts : CliOptions)
    (backend : Backend) : IO Unit := do
  let root ← projectRoot opts backend
  withProjectDaemonOwner home root backend
      (explicitControlDir? := opts.explicitControlDir?) fun owner =>
    runThenHoldUntilInterrupted owner do
      callBrokerQuiet root owner.client <| Request.ensure backend
      printResponse <| Response.success <| toJson <|
        mkSessionStatus .running root owner.client.controlDir (some owner.generation)
      (← IO.getStdout).flush
      IO.eprintln <|
        "beam: serving Beam session; interrupt this process or run when finished:\n" ++
        wrapperSessionCommand root owner.client.controlDir .stop

private def sessionStatus (opts : CliOptions) : IO Unit := do
  let root ← projectRootAny opts
  let sessionDir ← RocqBeam.Daemon.controlDirFor root opts.explicitControlDir?
  let result : SessionStatus ←
    match ← observeProjectRegistry root opts.explicitControlDir? with
    | .absent => pure <| mkSessionStatus .absent root sessionDir
    | .live entry => pure <| mkSessionStatus .running root sessionDir (some entry.daemonId)
    | .draining entry => pure <| mkSessionStatus .stopping root sessionDir (some entry.daemonId)
    | .selectorMismatch entry =>
        throw <| IO.userError <| sessionSelectorMismatchMessage root sessionDir entry
    | .recoveryRequired blocker =>
        pure <| mkSessionStatus .recoveryRequired root sessionDir blocker.generation?
          (some blocker.statusDetail)
  printResponse <| Response.success (toJson result)

def runCommand (home : System.FilePath) (opts : CliOptions) : IO Unit := do
  match opts.args with
  | [] | ["-h"] | ["--help"] | ["help"] => IO.println usage
  | "version" :: [] | "--version" :: [] => IO.println "rocq-beam 0.1.0"
  | "serve" :: [] => serveBackend home opts .rocq
  | "goals-after" :: path :: line :: character :: text =>
      let root ← projectRoot opts .rocq
      withProjectDaemon root .rocq (explicitControlDir? := opts.explicitControlDir?) fun client => do
        let version ← updateVersionForRocqGoals root client path
        callBroker root client {
          payload := .goals {
            backend := .rocq
            path
            version
            line := ← parseNatArg "line" line
            character := ← parseNatArg "character" character
            mode? := some .after
            compact? := some false
            ppFormat? := some .str
            text? := joinTextArgs text
          }
        }
  | "goals-prev" :: path :: line :: character :: text =>
      let root ← projectRoot opts .rocq
      withProjectDaemon root .rocq (explicitControlDir? := opts.explicitControlDir?) fun client => do
        let version ← updateVersionForRocqGoals root client path
        callBroker root client {
          payload := .goals {
            backend := .rocq
            path
            version
            line := ← parseNatArg "line" line
            character := ← parseNatArg "character" character
            mode? := some .before
            compact? := some false
            ppFormat? := some .str
            text? := joinTextArgs text
          }
        }
  | "doctor" :: [] =>
      doctor home opts .rocq
  | "open-files" :: [] =>
      let root ← projectRootAny opts
      withExistingProjectDaemon root (explicitControlDir? := opts.explicitControlDir?) fun client =>
        callBroker root client Request.openDocs
  | "cancel" :: requestId :: [] =>
      let root ← projectRootAny opts
      withExistingProjectDaemon root (explicitControlDir? := opts.explicitControlDir?) fun client =>
        callBroker root client <| Request.cancel requestId
  | "stats" :: [] =>
      let root ← projectRootAny opts
      withExistingProjectDaemon root (explicitControlDir? := opts.explicitControlDir?) fun client =>
        callBroker root client Request.stats
  | "status" :: [] =>
      sessionStatus opts
  | "stop" :: [] =>
      stopProjectSession opts
  | "recover" :: args =>
      recoverProjectSession opts args
  | _ =>
      throw <| IO.userError usage

end RocqBeam.Cli
