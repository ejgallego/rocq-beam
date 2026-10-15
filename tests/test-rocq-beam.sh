#!/usr/bin/env bash

# Copyright (c) 2026 Lean FRO LLC. All rights reserved.
# Released under Apache 2.0 license as described in the file LICENSE.
# Author: Emilio J. Gallego Arias

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=tests/lib/ci-steps.sh
. tests/lib/ci-steps.sh

ROCQ_BEAM_TEST_SUITE="${ROCQ_BEAM_TEST_SUITE:-rocq-beam}"

run_step "build" lake build \
  rocq-beam-cli \
  rocq-beam-daemon \
  rocq-beam-smoke-test

eval "$(opam env)"

if ! command -v coq-lsp > /dev/null 2>&1; then
  echo "missing coq-lsp; run tests/setup-rocq-opam.sh first" >&2
  exit 1
fi

run_step "wrapper tests" bash tests/test-wrapper.sh

run_step "CLI goals" python3 tests/test-cli.py

run_step "smoke test" .lake/build/bin/rocq-beam-smoke-test
