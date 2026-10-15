/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import RocqBeam.Broker.Protocol

namespace RocqBeam.Broker.Backend.Shared

def goalPpFormatValue (ppFormat? : Option GoalPpFormat) : String :=
  match ppFormat? with
  | some format => format.key
  | none => GoalPpFormat.str.key

end RocqBeam.Broker.Backend.Shared
