/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import RocqBeam.Path
import RocqBeam.Broker.Client
import RocqBeam.Broker.Protocol
import RocqBeam.Broker.Transport
import RocqBeamTest.Broker.ClientUtil

namespace RocqBeamTest.Broker.TestUtil

abbrev nullBrokerStdio : IO.Process.StdioConfig where
  stdin := .null
  stdout := .null
  stderr := .null

def daemonExe : IO System.FilePath := do
  pure <| (← IO.appPath).parent.getD (System.FilePath.mk ".") / "rocq-beam-daemon"

private def testPortBase : Nat :=
  49152

private def testPortSpan : Nat :=
  UInt16.size - testPortBase

private def testPortStride : Nat :=
  7919

private def testPortCandidate (seed attempt : Nat) : UInt16 :=
  (testPortBase + ((seed + attempt * testPortStride) % testPortSpan)).toUInt16

private def endpointAcceptsConnection (endpoint : RocqBeam.Broker.Endpoint) : IO Bool := do
  try
    let conn ← RocqBeam.Broker.Transport.connect endpoint
    RocqBeam.Broker.Transport.closeConnection conn
    pure true
  catch _ =>
    pure false

/--
Pick a test TCP port that is not accepting connections right now.

This is still subject to the usual close-before-spawn race, but it avoids the timestamp-derived
ports colliding with long-running local Beam daemons.
-/
partial def freshTcpPort (tries : Nat := 200) : IO UInt16 := do
  let seed ← IO.monoNanosNow
  let rec loop (attempt remaining : Nat) : IO UInt16 := do
    if remaining == 0 then
      throw <| IO.userError s!"could not find an unused local TCP port after {tries} attempts"
    let port := testPortCandidate seed attempt
    let endpoint : RocqBeam.Broker.Endpoint := .tcp port
    if ← endpointAcceptsConnection endpoint then
      loop (attempt + 1) (remaining - 1)
    else
      pure port
  loop 0 tries

def freshTcpEndpoint : IO RocqBeam.Broker.Endpoint := do
  pure (.tcp (← freshTcpPort))

def spawnRocqBroker
    (endpoint : RocqBeam.Broker.Endpoint)
    (root : System.FilePath)
    (rocqCmd : String := "coq-lsp") : IO (IO.Process.Child nullBrokerStdio) := do
  let port :=
    match endpoint with
    | .tcp port => port
  IO.Process.spawn {
    toStdioConfig := nullBrokerStdio
    cmd := (← daemonExe).toString
    args := #[
      "--port", toString port.toNat,
      "--root", root.toString,
      "--workspace-id", testWorkspaceId,
      "--rocq-cmd", rocqCmd
    ]
    setsid := true
  }

partial def waitForBrokerReady
    (endpoint : RocqBeam.Broker.Endpoint)
    (tries : Nat := 50) : IO Unit := do
  try
    let conn ← RocqBeam.Broker.Transport.connect endpoint
    RocqBeam.Broker.Transport.closeConnection conn
  catch _ =>
    if tries == 0 then
      throw <| IO.userError s!"timed out waiting for Beam daemon at {RocqBeam.Broker.Transport.endpointDescription endpoint}"
    IO.sleep 100
    waitForBrokerReady endpoint (tries - 1)

private def statsRoot? (resp : RocqBeam.Broker.Response) : Option String := do
  let result ← resp.result?
  result.getObjValAs? String "root" |>.toOption

private def brokerRoot? (endpoint : RocqBeam.Broker.Endpoint) : IO (Option String) := do
  try
    let result ← RocqBeam.Broker.sendRequestWithCallbacksTimeoutResult endpoint {
      RocqBeam.Broker.Request.stats with
      workspaceId? := some testWorkspaceId
    } testBrokerRequestTimeoutMs (server := .standalone)
    match result with
    | .ok resp =>
        if resp.ok then pure (statsRoot? resp) else pure none
    | .error _ => pure none
  catch _ =>
    pure none

partial def waitForBrokerReadyForRoot
    (endpoint : RocqBeam.Broker.Endpoint)
    (root : System.FilePath)
    (tries : Nat := 50) : IO Unit := do
  match ← brokerRoot? endpoint with
  | some daemonRoot =>
      if ← RocqBeam.sameFilePath (System.FilePath.mk daemonRoot) root then
        pure ()
      else
        throw <| IO.userError
          s!"test endpoint {RocqBeam.Broker.Transport.endpointDescription endpoint} already serves Beam root {daemonRoot}, not {root}"
  | none =>
      if tries == 0 then
        throw <| IO.userError
          s!"timed out waiting for Beam daemon at {RocqBeam.Broker.Transport.endpointDescription endpoint}"
      IO.sleep 100
      waitForBrokerReadyForRoot endpoint root (tries - 1)

end RocqBeamTest.Broker.TestUtil
