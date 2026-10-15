#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
eval "$(opam env)"
task_tmp="$(mktemp -d /tmp/rocq-beam-install-XXXXXX)"
cleanup() {
  case "$task_tmp" in /tmp/rocq-beam-install-*) rm -rf -- "$task_tmp" ;; esac
}
trap cleanup EXIT
export CODEX_HOME="$task_tmp/codex"
export CLAUDE_HOME="$task_tmp/claude"
export PI_CODING_AGENT_DIR="$task_tmp/pi"
export OPENCODE_CONFIG_DIR="$task_tmp/opencode"
export VIBE_HOME="$task_tmp/vibe"
prefix="$task_tmp/prefix"
bash scripts/install-rocq-beam.sh --prefix "$prefix" --all-skills
for agent_home in "$CODEX_HOME" "$CLAUDE_HOME" "$PI_CODING_AGENT_DIR" "$OPENCODE_CONFIG_DIR" "$VIBE_HOME"; do
  test -f "$agent_home/skills/rocq-beam/SKILL.md"
  test -f "$agent_home/skills/rocq-beam/.rocq-beam-skill"
  test ! -e "$agent_home/skills/lean-beam"
done
test "$(BEAM_HOME=/nonexistent "$prefix/bin/rocq-beam" version)" = 'rocq-beam 0.1.0'
python3 tests/test-cli.py --wrapper "$prefix/bin/rocq-beam"
# An unrelated skill directory must survive attempted replacement.
export CODEX_HOME="$task_tmp/unowned"
mkdir -p "$CODEX_HOME/skills/rocq-beam"
printf 'preserve me\n' > "$CODEX_HOME/skills/rocq-beam/SKILL.md"
if bash scripts/install-rocq-beam.sh --prefix "$prefix" --codex >"$task_tmp/refused.out" 2>"$task_tmp/refused.err"; then
  echo 'expected an unowned skill to be refused' >&2
  exit 1
fi
grep -Fq 'refusing to replace an unowned skill' "$task_tmp/refused.err"
test "$(cat "$CODEX_HOME/skills/rocq-beam/SKILL.md")" = 'preserve me'
echo 'isolated install passed'
