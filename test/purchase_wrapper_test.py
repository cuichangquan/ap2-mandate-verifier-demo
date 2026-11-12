"""Offline wrapper failure tests; only a fake docker executable is invoked."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'bin/purchase-demo'
FAKE = '''#!/bin/sh
printf '%s\\n' "$*" >> "$CALLS"
case "$*" in
  'compose -f compose.purchase.yml config --images') echo image:qa ;;
  'image inspect image:qa') exit 0 ;;
  create*) [ "$CASE" != locked ] ;;
  'compose -f compose.purchase.yml ps --status running -q authority buyer seller') [ "$CASE" != still_running ] || echo running-id ;;
  'compose -f compose.purchase.yml run --rm --no-deps init bundle exec ruby purchase_demo/tls_rotate.rb --services-stopped') [ "$CASE" != rotate_failed ] ;;
  'compose -f compose.purchase.yml up -d --no-build authority buyer seller') [ "$CASE" != restart_failed ] ;;
  'compose -f compose.purchase.yml exec -T authority bundle exec ruby purchase_demo/readiness.rb authority') exit 0 ;;
  *) exit 0 ;;
esac
'''

class WrapperTest(unittest.TestCase):
    def invoke(self, case):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'compose.purchase.yml').touch()
            docker = root / 'docker'
            docker.write_text(FAKE)
            docker.chmod(0o755)
            calls = root / 'calls'
            env = dict(os.environ, PATH=f'{root}:' + os.environ['PATH'], CASE=case,
                       CALLS=str(calls), COMPOSE_PROJECT_NAME='wrapper-qa')
            result = subprocess.run(['sh', str(SCRIPT), 'rotate'], cwd=root,
                                    env=env, capture_output=True, text=True, timeout=10)
            return result, calls.read_text().splitlines()

    def test_retained_volumes_without_existing_init_container(self):
        result, calls = self.invoke('success')
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('compose -f compose.purchase.yml config --images', calls)
        self.assertFalse(any(' images ' in call for call in calls))
        self.assertIn('TLS rotation verified', result.stdout)

    def test_partial_restart_failure_stops_every_role(self):
        result, calls = self.invoke('restart_failed')
        self.assertNotEqual(0, result.returncode)
        self.assertIn('stop -t 30 authority buyer seller', calls[-2])
        self.assertTrue(calls[-1].startswith('rm wrapper-qa-tls-maintenance-lock'))
        self.assertNotIn('TLS rotation verified', result.stdout)

    def test_rotation_failure_keeps_roles_stopped(self):
        result, calls = self.invoke('rotate_failed')
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(any(' up ' in call for call in calls))
        self.assertIn('stop -t 30 authority buyer seller', calls[-2])

    def test_duplicate_wrapper_does_not_stop_other_work(self):
        result, calls = self.invoke('locked')
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(any(' stop ' in call or call.startswith('rm ') for call in calls))

    def test_running_services_prevent_rotation(self):
        result, calls = self.invoke('still_running')
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(any('tls_rotate.rb' in call for call in calls))

if __name__ == '__main__':
    unittest.main()
