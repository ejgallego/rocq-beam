/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import RocqBeam.Broker.Protocol
import RocqBeamTest.Broker.BackendMessageTest
import RocqBeamTest.Broker.TestUtil
import Lean

open Lean

namespace RocqBeamTest.Broker.RocqSmokeTest

open RocqBeamTest.Broker.TestUtil

private def repoRoot : IO System.FilePath := do
  IO.FS.realPath <| System.FilePath.mk "."

private def rocqRoot : IO System.FilePath := do
  IO.FS.realPath <| (← repoRoot) / "tests" / "rocq" / "Minimal"

private def expectTwoTrueGoals (payload : Json) : IO Unit := do
  let goalConfig ← IO.ofExcept <| payload.getObjVal? "goals"
  let goals ← IO.ofExcept <| goalConfig.getObjVal? "goals"
  let .arr goals := goals
    | throw <| IO.userError s!"expected goals array, got {goals.compress}"
  if goals.size != 2 then
    throw <| IO.userError s!"expected 2 goals, got {goals.size}: {payload.compress}"
  for goal in goals do
    let ty ← IO.ofExcept <| goal.getObjValAs? String "ty"
    if ty.trimAscii != "True" then
      throw <| IO.userError s!"expected goal type True, got {ty}"

private def expectNonemptyError (payload : Json) : IO Unit := do
  let err ← IO.ofExcept <| payload.getObjVal? "error"
  match err with
  | .str text =>
      if text.trimAscii.isEmpty then
        throw <| IO.userError s!"expected non-empty error field, got {payload.compress}"
  | .arr items =>
      if items.isEmpty then
        throw <| IO.userError s!"expected non-empty structured error field, got {payload.compress}"
  | .null =>
      throw <| IO.userError s!"expected non-empty error field, got {payload.compress}"
  | _ =>
      pure ()

private def expectSurfacedError (resp : RocqBeam.Broker.Response) : IO Unit := do
  if resp.ok then
    throw <| IO.userError s!"expected broker error, got success {(toJson resp).compress}"
  let some err := resp.error?
    | throw <| IO.userError s!"expected broker error payload, got {(toJson resp).compress}"
  if err.code == "internalError" || err.code == "workerExited" then
    throw <| IO.userError s!"expected surfaced Rocq error, got {err.code}: {err.message}"
  if err.message.trimAscii.isEmpty then
    throw <| IO.userError s!"expected non-empty surfaced Rocq error, got {(toJson resp).compress}"

private def updateVersion
    (endpoint : RocqBeam.Broker.Endpoint)
    (path : String) : IO Nat := do
  let resp ← runClient endpoint {
    payload := .updateFile { backend := .rocq, path }
  }
  let result ← requireUpdateFileResult s!"rocq update version for {path}" (← expectOk resp)
  pure result.version

def main : IO Unit := do
  RocqBeamTest.Broker.BackendMessageTest.check
  let endpoint ← freshTcpEndpoint
  let root ← rocqRoot
  let broker ← spawnRocqBroker endpoint root ((← IO.getEnv "ROCQ_BEAM_COQ_LSP").getD "coq-lsp")
  try
    waitForBrokerReadyForRoot endpoint root
    expectErrCode (← runClient endpoint (RocqBeam.Broker.Request.ensure .lean)) "invalidParams"
    discard <| expectOk (← runClient endpoint (RocqBeam.Broker.Request.ensure .rocq))
    let unsupportedSync ← runClient endpoint {
      payload := .syncFile { backend := .rocq, path := "Demo.v" }
    }
    expectErrCode unsupportedSync "invalidParams"
    let demoVersion ← updateVersion endpoint "Demo.v"
    let semiVersion ← updateVersion endpoint "Semi.v"
    let errorVersion ← updateVersion endpoint "Error.v"
    let doneVersion ← updateVersion endpoint "Done.v"
    let goals ← expectOk <| ← runClient endpoint {
      payload := .goals {
        backend := .rocq
        path := "Demo.v"
        version := demoVersion
        line := 2
        character := 8
        mode? := some .after
        compact? := some false
      }
    }
    expectTwoTrueGoals goals

    let semiGoals ← expectOk <| ← runClient endpoint {
      payload := .goals {
        backend := .rocq
        path := "Semi.v"
        version := semiVersion
        line := 2
        character := 3
        mode? := some .before
        text? := some "split."
        compact? := some false
      }
    }
    expectTwoTrueGoals semiGoals

    let errorGoals ← expectOk <| ← runClient endpoint {
      payload := .goals {
        backend := .rocq
        path := "Error.v"
        version := errorVersion
        line := 2
        character := 8
        mode? := some .after
        compact? := some false
      }
    }
    expectTwoTrueGoals errorGoals

    let errorPayload ← expectOk <| ← runClient endpoint {
      payload := .goals {
        backend := .rocq
        path := "Error.v"
        version := errorVersion
        line := 4
        character := 2
        mode? := some .after
        compact? := some false
      }
    }
    expectNonemptyError errorPayload

    let zeroGoalResp ← runClient endpoint {
      payload := .goals {
        backend := .rocq
        path := "Done.v"
        version := doneVersion
        line := 3
        character := 0
        mode? := some .before
        text? := some "exact I."
        compact? := some false
      }
    }
    expectSurfacedError zeroGoalResp

    let stats ← expectOk <| ← runClient endpoint {
      RocqBeam.Broker.Request.stats with
      workspaceId? := some testWorkspaceId
    }
    expectOpCountAtLeast stats "rocq" "goals" 5
    discard <| expectOk <| ← runClient endpoint RocqBeam.Broker.Request.shutdown
  finally
    try
      broker.kill
    catch _ =>
      pure ()

end RocqBeamTest.Broker.RocqSmokeTest

def main := RocqBeamTest.Broker.RocqSmokeTest.main
