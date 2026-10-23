/-
Copyright (c) 2020 Marc Huisinga. All rights reserved.
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Marc Huisinga, Wojciech Nawrocki, Emilio J. Gallego Arias
-/

import Lean.Data.Lsp.Communication

open Lean
open Lean.JsonRpc

namespace RocqBeam.Broker

/-- Backend messages retain integer server error codes, including LSP RequestFailed (-32803).
Lean's closed `JsonRpc.ErrorCode` enum is insufficient for the coq-lsp wire protocol. -/
inductive BackendMessage where
  | request (id : RequestID) (method : String) (params? : Option Json.Structured)
  | notification (method : String) (params? : Option Json.Structured)
  | response (id : RequestID) (result : Json)
  | responseError (id : RequestID) (code : Int) (message : String) (data? : Option Json)

instance : FromJson BackendMessage where
  fromJson? j := do
    let "2.0" ← j.getObjVal? "jsonrpc"
      | throw "only version 2.0 of JSON RPC is supported"
    (do let id ← j.getObjValAs? RequestID "id"
        let method ← j.getObjValAs? String "method"
        let params? := j.getObjValAs? Json.Structured "params"
        pure (.request id method params?.toOption)) <|>
    (do let method ← j.getObjValAs? String "method"
        let params? := j.getObjValAs? Json.Structured "params"
        pure (.notification method params?.toOption)) <|>
    (do let id ← j.getObjValAs? RequestID "id"
        let result ← j.getObjVal? "result"
        pure (.response id result)) <|>
    (do let id ← j.getObjValAs? RequestID "id"
        let err ← j.getObjVal? "error"
        let code ← err.getObjValAs? Int "code"
        let message ← err.getObjValAs? String "message"
        let data? := err.getObjVal? "data"
        pure (.responseError id code message data?.toOption))

def BackendMessage.read (stream : IO.FS.Stream) : IO BackendMessage := do
  let text ← stream.readLspMessageAsString
  match Json.parse text >>= fromJson? with
  | .ok message => pure message
  | .error err => throw <| IO.userError s!"Cannot read LSP message: {err}"

end RocqBeam.Broker
