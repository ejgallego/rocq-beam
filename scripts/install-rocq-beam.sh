#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${ROCQ_BEAM_INSTALL_PREFIX:-$HOME/.local}"
targets=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -ge 2 ] || { echo "--prefix requires an absolute path" >&2; exit 1; }
      prefix="$2"; shift 2 ;;
    --codex|--claude|--pi|--opencode|--vibe)
      targets+=("${1#--}"); shift ;;
    --all-skills) targets+=(codex claude pi opencode vibe); shift ;;
    -h|--help)
      echo "Usage: $0 [--prefix DIR] [--codex|--claude|--pi|--opencode|--vibe|--all-skills]"
      exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
case "$prefix" in
  /*) ;;
  *) echo "--prefix must be absolute" >&2; exit 1 ;;
esac
[ "$prefix" != / ] || { echo "--prefix must not be /" >&2; exit 1; }

# Build before changing any installation paths.
(cd "$repo_root" && lake build rocq-beam-cli rocq-beam-daemon)
runtime="$prefix/share/rocq-beam"
if [ -L "$runtime" ] || { [ -e "$runtime" ] && [ ! -f "$runtime/.rocq-beam-runtime" ]; }; then
  echo "refusing to replace an unowned runtime: $runtime" >&2
  exit 1
fi
for target in "${targets[@]}"; do
  case "$target" in
    codex) agent_home="${CODEX_HOME:-$HOME/.codex}" ;;
    claude) agent_home="${CLAUDE_HOME:-$HOME/.claude}" ;;
    pi) agent_home="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" ;;
    opencode) agent_home="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}" ;;
    vibe) agent_home="${VIBE_HOME:-$HOME/.vibe}" ;;
  esac
  skill="$agent_home/skills/rocq-beam"
  if [ -L "$skill" ] || { [ -e "$skill" ] && [ ! -f "$skill/.rocq-beam-skill" ]; }; then
    echo "refusing to replace an unowned skill: $skill" >&2
    exit 1
  fi
done
mkdir -p "$prefix/bin" "$runtime/libexec" "$runtime/scripts"
install -m 755 "$repo_root/.lake/build/bin/rocq-beam-cli" "$runtime/libexec/rocq-beam-cli"
install -m 755 "$repo_root/.lake/build/bin/rocq-beam-daemon" "$runtime/libexec/rocq-beam-daemon"
cp "$repo_root/scripts/rocq-beam" "$runtime/scripts/rocq-beam"
printf 'rocq-beam\n' > "$runtime/.rocq-beam-runtime"
ln -sfn "$runtime/scripts/rocq-beam" "$prefix/bin/rocq-beam"
for target in "${targets[@]}"; do
  case "$target" in
    codex) agent_home="${CODEX_HOME:-$HOME/.codex}" ;;
    claude) agent_home="${CLAUDE_HOME:-$HOME/.claude}" ;;
    pi) agent_home="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" ;;
    opencode) agent_home="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}" ;;
    vibe) agent_home="${VIBE_HOME:-$HOME/.vibe}" ;;
  esac
  skill="$agent_home/skills/rocq-beam"
  mkdir -p "$skill"
  cp "$repo_root/skills/rocq-beam/SKILL.md" "$skill/SKILL.md"
  mkdir -p "$skill/agents"
  cp "$repo_root/skills/rocq-beam/agents/openai.yaml" "$skill/agents/openai.yaml"
  printf 'rocq-beam\n' > "$skill/.rocq-beam-skill"
done
printf 'Installed %s\n' "$prefix/bin/rocq-beam"
