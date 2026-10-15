namespace RocqBeam.Cli

def usage : String := String.intercalate "\n" [
  "Usage: rocq-beam [--root PATH] [--session-dir DIR] COMMAND",
  "  serve                          own a foreground coq-lsp session",
  "  goals-after PATH LINE CHARACTER [TEXT...]",
  "  goals-prev PATH LINE CHARACTER [TEXT...]",
  "  doctor | status | open-files | stats",
  "  stop                           requires --root",
  "  recover --generation ID | --force   requires --root",
  "  version"
]

end RocqBeam.Cli
