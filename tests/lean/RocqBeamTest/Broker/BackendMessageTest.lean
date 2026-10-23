/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import RocqBeam.Broker.BackendMessage
import RocqBeam.Broker.Errors

open Lean
open RocqBeam.Broker

namespace RocqBeamTest.Broker.BackendMessageTest

private def errorMessage (code : Json) : Json :=
  Json.mkObj [
    ("jsonrpc", toJson "2.0"),
    ("id", toJson "goals-7"),
    ("error", Json.mkObj [
      ("code", code),
      ("message", toJson "Unable to unify \"0\" with \"eval v a\". é"),
      ("data", Json.mkObj [("detail", toJson #["tactic", "failure"])])
    ])
  ]

private def framed (message : Json) : String :=
  let body := message.compress
  s!"Content-Length: {body.utf8ByteSize}\r\n\r\n{body}"

def check : IO Unit := do
  for (code, expectedName) in #[(-32803, "-32803"), (-32802, "-32802"),
      (-32042, "-32042"), (-32800, "requestCancelled")] do
    let json := errorMessage (toJson (code : Int))
    let next := Json.mkObj [
      ("jsonrpc", toJson "2.0"), ("id", toJson (8 : Nat)), ("result", Json.null)]
    let buffer ← IO.mkRef ({ data := (framed json ++ framed next).toUTF8 } : IO.FS.Stream.Buffer)
    let stream := IO.FS.Stream.ofBuffer buffer
    let .responseError id actualCode message data? ← BackendMessage.read stream
      | throw <| IO.userError "expected typed backend response error"
    unless id == .str "goals-7" && actualCode == code do
      throw <| IO.userError "backend error identity/code changed"
    let failure := backendResponseFailure actualCode message data?
    let err ← IO.ofExcept <| json.getObjVal? "error"
    unless failure.error.code == expectedName &&
        toJson failure.error.message == (← IO.ofExcept <| err.getObjVal? "message") &&
        failure.error.data? == (err.getObjVal? "data").toOption do
      throw <| IO.userError "backend failure lost its code, message, or data"
    let .response nextId .null ← BackendMessage.read stream
      | throw <| IO.userError "error response disrupted the next LSP frame"
    unless nextId == 8 do
      throw <| IO.userError "next LSP response id changed"

  for code in #[toJson "-32803", Json.null, toJson (1.5 : Float)] do
    if (fromJson? (α := BackendMessage) (errorMessage code)).isOk then
      throw <| IO.userError "accepted a non-integer backend error code"
  let notification := Json.mkObj [
    ("jsonrpc", toJson "2.0"), ("method", toJson "textDocument/publishDiagnostics")]
  let .notification "textDocument/publishDiagnostics" none ←
      IO.ofExcept (fromJson? (α := BackendMessage) notification)
    | throw <| IO.userError "notification decoding changed"

end RocqBeamTest.Broker.BackendMessageTest
