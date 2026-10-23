#!/usr/bin/env python3
"""Exercise the public CLI against real coq-lsp, including probe isolation."""
import argparse
import json
import time
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--wrapper', type=Path, default=repo / 'scripts/rocq-beam')
args = parser.parse_args()
wrapper = args.wrapper.resolve()

def call(root, *parts, success=True):
    result = subprocess.run([str(wrapper), '--root', str(root), *parts],
                            capture_output=True, text=True, timeout=30)
    if success:
        assert result.returncode == 0, (parts, result.stdout, result.stderr)
        payload = json.loads(result.stdout)
        assert payload['ok'], payload
        return payload['result']
    assert result.returncode != 0, (parts, result.stdout, result.stderr)
    return result

def two_goals(payload):
    goals = payload['goals']['goals']
    assert len(goals) == 2, payload
    assert all(goal['ty'].strip() == 'True' for goal in goals), payload

with tempfile.TemporaryDirectory(prefix='rocq-beam-cli-') as temp:
    root = Path(temp)
    shutil.copytree(repo / 'tests/rocq/Minimal', root, dirs_exist_ok=True)
    (root / '.beam').mkdir()
    sentinel = root / '.beam' / 'sentinel'
    sentinel.write_text('Lean Beam state is independent\n')
    before = {p.name: p.read_bytes() for p in root.glob('*.v')}
    call(root, 'goals-after', 'Demo.v', '2', '8', success=False)
    with (root / 'owner.stderr').open('w+') as stderr:
        owner = subprocess.Popen([str(wrapper), '--root', str(root), 'serve'],
                                 stdout=subprocess.DEVNULL, stderr=stderr)
        try:
            deadline = time.monotonic() + 60
            while 'serving Beam session' not in (root / 'owner.stderr').read_text():
                if owner.poll() is not None:
                    raise AssertionError((root / 'owner.stderr').read_text())
                assert time.monotonic() < deadline, 'owner did not report readiness'
                time.sleep(.1)
            assert call(root, 'status')['state'] == 'running'
            two_goals(call(root, 'goals-after', 'Demo.v', '2', '8'))
            two_goals(call(root, 'goals-prev', 'Semi.v', '2', '3', 'split.'))
            # A speculative prefix must not become the basis of the next request.
            baseline = call(root, 'goals-prev', 'Semi.v', '2', '3')
            assert len(baseline['goals']['goals']) == 1, baseline
            two_goals(call(root, 'goals-prev', 'Semi.v', '2', '3', 'split.'))
            # BUC-0011: a valid LSP RequestFailed response is a tactic failure,
            # not a decoder exception or a reason to replace the backend worker.
            status_before = call(root, 'status')
            stats_before = call(root, 'stats')
            failed = call(root, 'goals-prev', 'Semi.v', '2', '3',
                          'reflexivity.', success=False)
            failure = json.loads(failed.stdout)
            assert not failure['ok'], failure
            assert failure['error']['code'] == '-32803', failure
            assert failure['error']['message'].strip(), failure
            two_goals(call(root, 'goals-prev', 'Semi.v', '2', '3', 'split.'))
            baseline_after = call(root, 'goals-prev', 'Semi.v', '2', '3')
            assert baseline_after == baseline, (baseline, baseline_after)
            assert call(root, 'status') == status_before
            stats_after = call(root, 'stats')
            assert stats_after['sessions']['rocq'] == stats_before['sessions']['rocq']
            for key in ('sessionStarts', 'sessionRestarts', 'workerExitedCount'):
                assert (stats_after['byBackend']['rocq'][key] ==
                        stats_before['byBackend']['rocq'][key]), (key, stats_after)
            error = call(root, 'goals-after', 'Error.v', '4', '2')
            assert error.get('error'), error
            call(root, 'run-at', 'Demo.v', '2', '8', 'split.', success=False)
            call(root, 'serve', 'lean', success=False)
            call(root, 'doctor', 'lean', success=False)
            call(root, 'goals-after', 'Demo.v', '-1', '8', success=False)
            assert (root / '.rocq-beam' / 'rocq-beam-daemon.json').is_file()
            assert sentinel.read_text() == 'Lean Beam state is independent\n'
            assert {p.name: p.read_bytes() for p in root.glob('*.v')} == before
            call(root, 'stop')
            assert owner.wait(timeout=30) == 0
            assert call(root, 'status')['state'] == 'absent'
        finally:
            if owner.poll() is None:
                try:
                    call(root, 'stop')
                    owner.wait(timeout=30)
                except Exception:
                    owner.kill()
                    owner.wait(timeout=10)
print('CLI goals and isolation passed')
