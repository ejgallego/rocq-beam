/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import RocqBeam.Broker.Client
import RocqBeam.Broker.Protocol

open Lean

namespace RocqBeamTest.Broker.TestUtil

def testWorkspaceId : RocqBeam.Broker.WorkspaceId :=
  "beam-test-project"

/-- Keep test broker requests bounded without imposing production-scale timing assumptions. -/
def testBrokerRequestTimeoutMs : Nat :=
  120000

/--
Address ordinary fixture requests to the workspace created by the broker test harness.

Tests of missing workspace identity must bypass this adapter and dispatch or send the raw request.
Optional and process-wide operations remain unscoped.
-/
def inFixtureWorkspace (req : RocqBeam.Broker.Request) : RocqBeam.Broker.Request :=
  match req.op.workspaceScope with
  | .required =>
      if req.workspaceId?.isSome || req.handle?.isSome then req
      else { req with workspaceId? := some testWorkspaceId }
  | .optional | .none => req

structure ProgressEvent where
  clientRequestId? : Option String := none
  progress : RocqBeam.Broker.SyncFileProgress

private def clientResponse
    (label : String)
    (result : Except RocqBeam.Broker.BrokerClientFailure RocqBeam.Broker.Response) :
    IO RocqBeam.Broker.Response :=
  match result with
  | .ok response => pure response
  | .error failure => throw <| IO.userError s!"{label}: {failure.detail}"

def runClientWithStream
    (endpoint : RocqBeam.Broker.Endpoint)
    (req : RocqBeam.Broker.Request) :
    IO (RocqBeam.Broker.Response × Array RocqBeam.Broker.SyncFileProgress × Array RocqBeam.Broker.StreamDiagnostic) := do
  let progressRef ← IO.mkRef #[]
  let diagnosticRef ← IO.mkRef #[]
  let result ← RocqBeam.Broker.sendRequestWithCallbacksTimeoutResult endpoint (inFixtureWorkspace req)
    testBrokerRequestTimeoutMs {
    onFileProgress := fun progress =>
      progressRef.modify fun seen => seen.push progress
    onDiagnostic := fun diagnostic =>
      diagnosticRef.modify fun seen => seen.push diagnostic
  } .standalone
  let resp ← clientResponse "broker request failed" result
  pure (resp, ← progressRef.get, ← diagnosticRef.get)

def runClientWithProgress
    (endpoint : RocqBeam.Broker.Endpoint)
    (req : RocqBeam.Broker.Request) : IO (RocqBeam.Broker.Response × Array ProgressEvent) := do
  let progressRef ← IO.mkRef #[]
  let result ← RocqBeam.Broker.sendRequestWithStreamTimeoutResult endpoint (inFixtureWorkspace req)
      testBrokerRequestTimeoutMs (server := .standalone) fun stream =>
    match stream with
    | .fileProgress clientRequestId? progress =>
        progressRef.modify fun seen => seen.push { clientRequestId?, progress }
    | .diagnostic .. | .response .. => pure ()
  let resp ←
    match result with
    | .ok response => pure response
    | .error failure =>
        throw <| IO.userError s!"broker request failed: {failure.detail}"
  pure (resp, ← progressRef.get)

def runClient (endpoint : RocqBeam.Broker.Endpoint) (req : RocqBeam.Broker.Request) : IO RocqBeam.Broker.Response := do
  clientResponse "broker request failed" <|
    ← RocqBeam.Broker.sendRequestWithCallbacksTimeoutResult endpoint (inFixtureWorkspace req)
      testBrokerRequestTimeoutMs
      (server := .standalone)

def requireFileProgress (label : String) (resp : RocqBeam.Broker.Response) :
    IO RocqBeam.Broker.SyncFileProgress := do
  let some progress := resp.fileProgress?
    | throw <| IO.userError s!"expected {label} to include top-level fileProgress"
  pure progress

def requireSyncFileResult
    (label : String)
    (payload : Json) : IO RocqBeam.Broker.SyncFileResult := do
  match fromJson? payload with
  | .ok result => pure result
  | .error err => throw <| IO.userError s!"{label}: failed to decode sync result: {err}"

def requireUpdateFileResult
    (label : String)
    (payload : Json) : IO RocqBeam.Broker.UpdateFileResult := do
  match fromJson? payload with
  | .ok result => pure result
  | .error err => throw <| IO.userError s!"{label}: failed to decode update result: {err}"

def expectNoReplayDiagnosticsField (label : String) (payload : Json) : IO Unit := do
  match payload.getObjVal? "diagnostics" with
  | .ok diagnostics =>
      match diagnostics.getObjVal? "items" with
      | .ok items =>
          throw <| IO.userError
            s!"expected {label} payload to omit replayed diagnostics, got {items.compress}"
      | .error _ => pure ()
  | .error _ => pure ()

def requireFinalStreamResponse
    (label : String)
    (messages : Array RocqBeam.Broker.StreamMessage) : IO RocqBeam.Broker.Response := do
  if messages.isEmpty then
    throw <| IO.userError s!"expected {label} stream messages"
  let responseCount := messages.foldl (init := 0) fun acc msg =>
    acc + match msg with
      | .response .. => 1
      | _ => 0
  if responseCount != 1 then
    throw <| IO.userError s!"expected exactly one {label} response message, got {(toJson messages).compress}"
  let some last := messages.back?
    | throw <| IO.userError s!"expected {label} final response"
  match last with
  | .response _ resp => pure resp
  | _ =>
      throw <| IO.userError
        s!"expected {label} response to arrive last, got {(toJson messages).compress}"

def runBrokerStream
    (endpoint : RocqBeam.Broker.Endpoint)
    (req : RocqBeam.Broker.Request) : IO (Array RocqBeam.Broker.StreamMessage) := do
  let messagesRef ← IO.mkRef #[]
  match ← RocqBeam.Broker.sendRequestWithStreamTimeoutResult endpoint (inFixtureWorkspace req)
      testBrokerRequestTimeoutMs (server := .standalone) fun message =>
      messagesRef.modify (·.push message) with
  | .ok _ => pure (← messagesRef.get)
  | .error failure =>
      throw <| IO.userError s!"broker stream request failed: {failure.detail}"

def requireSuccessStream
    (label : String)
    (messages : Array RocqBeam.Broker.StreamMessage) : IO (Array RocqBeam.Broker.StreamMessage) := do
  let response ← requireFinalStreamResponse label messages
  unless response.ok do
    throw <| IO.userError s!"expected {label} stream success, got {(toJson response).compress}"
  pure messages

def requireFailedStream
    (label : String)
    (messages : Array RocqBeam.Broker.StreamMessage) : IO (Array RocqBeam.Broker.StreamMessage) := do
  let response ← requireFinalStreamResponse label messages
  if response.ok then
    throw <| IO.userError s!"expected {label} stream failure"
  pure messages

def expectStreamClientRequestId
    (label : String)
    (messages : Array RocqBeam.Broker.StreamMessage)
    (expected : Option String) : IO Unit := do
  messages.forM fun message =>
    unless message.clientRequestId? == expected do
      throw <| IO.userError
        s!"expected every {label} stream envelope to carry request id {expected}, got {(toJson message).compress}"

def requireAnyStreamDiagnostics
    (label : String)
    (messages : Array RocqBeam.Broker.StreamMessage) : IO (Array RocqBeam.Broker.StreamDiagnostic) := do
  let diagnostics := messages.filterMap fun
    | .diagnostic _ diagnostic => some diagnostic
    | _ => none
  if diagnostics.isEmpty then
    throw <| IO.userError s!"expected {label} to stream diagnostics, got {(toJson messages).compress}"
  pure diagnostics

def requireAnyStreamFileProgress
    (label : String)
    (messages : Array RocqBeam.Broker.StreamMessage) : IO (Array RocqBeam.Broker.SyncFileProgress) := do
  let progress := messages.filterMap fun
    | .fileProgress _ progress => some progress
    | _ => none
  if progress.isEmpty then
    throw <| IO.userError s!"expected {label} to stream fileProgress, got {(toJson messages).compress}"
  pure progress

def expectDiagnosticsForPath
    (label path : String)
    (diagnostics : Array RocqBeam.Broker.StreamDiagnostic) : IO Unit := do
  unless diagnostics.all (fun diagnostic => diagnostic.path == path) do
    throw <| IO.userError s!"expected {label} diagnostics for {path}, got {(toJson diagnostics).compress}"

def expectNonErrorDiagnosticsForPath
    (label path : String)
    (diagnostics : Array RocqBeam.Broker.StreamDiagnostic) : IO Unit := do
  unless diagnostics.all (fun diagnostic =>
      diagnostic.path == path && diagnostic.severity? != some .error) do
    throw <| IO.userError
      s!"expected {label} non-error diagnostics for {path}, got {(toJson diagnostics).compress}"

def expectWarningDiagnosticPresent
    (label : String)
    (diagnostics : Array RocqBeam.Broker.StreamDiagnostic) : IO Unit := do
  unless diagnostics.any (fun diagnostic => diagnostic.severity? == some .warning) do
    throw <| IO.userError
      s!"expected {label} diagnostics to include at least one warning, got {(toJson diagnostics).compress}"

def expectOk (resp : RocqBeam.Broker.Response) : IO Json := do
  match resp with
  | .successResult result .. => pure result
  | .errorResult .. =>
      throw <| IO.userError s!"unexpected Beam daemon error: {(toJson resp).compress}"

def expectErrCode (resp : RocqBeam.Broker.Response) (code : String) : IO Unit := do
  match resp with
  | .successResult .. =>
      throw <| IO.userError s!"expected error {code}, got success {(toJson resp).compress}"
  | .errorResult failure =>
      if failure.error.code != code && failure.error.code != "-32602" then
        throw <| IO.userError s!"expected error {code}, got {(toJson resp).compress}"

def expectOpCountAtLeast (payload : Json) (backend op : String) (minCount : Nat) : IO Unit := do
  let byBackend ← IO.ofExcept <| payload.getObjVal? "byBackend"
  let backendPayload ← IO.ofExcept <| byBackend.getObjVal? backend
  let ops ← IO.ofExcept <| backendPayload.getObjVal? "ops"
  let opPayload ← IO.ofExcept <| ops.getObjVal? op
  let count ← IO.ofExcept <| opPayload.getObjValAs? Nat "count"
  if count < minCount then
    throw <| IO.userError s!"expected {backend}/{op} count >= {minCount}, got {count}"

def expectBackendMetricAtLeast (payload : Json) (backend field : String) (minCount : Nat) : IO Unit := do
  let byBackend ← IO.ofExcept <| payload.getObjVal? "byBackend"
  let backendPayload ← IO.ofExcept <| byBackend.getObjVal? backend
  let count ← IO.ofExcept <| backendPayload.getObjValAs? Nat field
  if count < minCount then
    throw <| IO.userError s!"expected {backend}.{field} >= {minCount}, got {count}"

def expectOpMetricAtLeast (payload : Json) (backend op field : String) (minCount : Nat) : IO Unit := do
  let byBackend ← IO.ofExcept <| payload.getObjVal? "byBackend"
  let backendPayload ← IO.ofExcept <| byBackend.getObjVal? backend
  let ops ← IO.ofExcept <| backendPayload.getObjVal? "ops"
  let opPayload ← IO.ofExcept <| ops.getObjVal? op
  let count ← IO.ofExcept <| opPayload.getObjValAs? Nat field
  if count < minCount then
    throw <| IO.userError s!"expected {backend}/{op}.{field} >= {minCount}, got {count}"

end RocqBeamTest.Broker.TestUtil
