import Lake
open Lake DSL
open System

package "rocq-beam" where
  enableArtifactCache := true
  restoreAllArtifacts := true

target beamControlDirObj (pkg) : FilePath := do
  let srcFile := pkg.dir / "RocqBeam" / "Native" / "control_dir.c"
  let oFile := pkg.buildDir / "native" / "control_dir.o"
  let srcTarget ← inputTextFile srcFile
  buildFileAfterDep oFile srcTarget fun srcFile => do
    compileO oFile srcFile #["-I", (← getLeanIncludeDir).toString, "-fPIC"]

lean_lib RocqBeam where
  moreLinkObjs := #[beamControlDirObj]

lean_lib RocqBeamTest where
  srcDir := "tests/lean"

@[default_target]
lean_exe "rocq-beam-cli" where
  root := `RocqBeam.Cli

@[default_target]
lean_exe "rocq-beam-daemon" where
  root := `RocqBeam.Broker.ServerMain

lean_exe "rocq-beam-smoke-test" where
  srcDir := "tests/lean"
  root := `RocqBeamTest.Broker.RocqSmokeTest
