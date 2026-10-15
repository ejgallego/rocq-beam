/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import RocqBeam.Cli.Project
import RocqBeam.Daemon.Protocol

open Lean

namespace RocqBeam.Cli

open RocqBeam.Broker

/-- The complete temporary Rocq backend configuration in a wrapper-owned session. -/
structure RocqBackendConfig where
  command : String
  deriving Repr

/-- A nonempty set of complete backend configurations for one wrapper-owned workspace. -/
inductive BackendSet where
  /-- A Rocq-owned session uses only the temporary Rocq backend. -/
  | rocq (rocq : RocqBackendConfig)
  deriving Repr

namespace BackendSet

private def rocqOnlyDescriptorBundleId : String :=
  "default"

private def descriptorBundleId : BackendSet → String
  | .rocq _ => rocqOnlyDescriptorBundleId

/-- Lower a complete internal backend set into the private session descriptor wire shape. -/
def toWorkspaceBinding
    (backends : BackendSet)
    (workspaceId : WorkspaceId)
    (root : System.FilePath) : RocqBeam.Daemon.WorkspaceBinding :=
  let common : RocqBeam.Daemon.WorkspaceBinding := {
    workspaceId
    root := root.toString
    bundleId := backends.descriptorBundleId
  }
  match backends with
  | .rocq rocqConfig => {
      common with
      rocqCmd? := some rocqConfig.command
    }

/-- Command-line arguments that install this complete backend set in a Beam daemon. -/
def daemonArgs : BackendSet → Array String
  | .rocq rocqConfig =>
      #["--rocq-cmd", rocqConfig.command]

private def hashFields
    (backends : BackendSet)
    (daemonBin : System.FilePath) : List String :=
  match backends with
  | .rocq rocqConfig =>
      ["", "", rocqConfig.command, daemonBin.toString, backends.descriptorBundleId]

end BackendSet

/-- Source configuration for one wrapper-owned daemon generation. -/
structure DesiredConfig where
  root : System.FilePath
  backends : BackendSet
  daemonBin : System.FilePath
  deriving Repr

/-- Hash the complete desired configuration using the established wrapper session field order. -/
def DesiredConfig.configHash (config : DesiredConfig) : String :=
  let fields := config.root.toString :: config.backends.hashFields config.daemonBin
  let hash := fields.foldl (fun acc field =>
    field.toUTF8.foldl (fun acc byte => (acc ^^^ byte.toUInt64) * 1099511628211)
      ((acc ^^^ 0) * 1099511628211)) (14695981039346656037 : UInt64)
  s!"{hash.toNat}"

end RocqBeam.Cli
