"""Release checks for the account connection boundary."""

import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

import devnull


class CallbackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.pending = root / "pending.json"
        self.account = root / "account.json"
        self.auth_result = root / "last_auth_result.json"
        self.pending.write_text(json.dumps({
            "state": "expected", "verifier": "private-verifier", "created_at": int(time.time())
        }), encoding="utf-8")
        self.patch_pending = patch.object(devnull, "PENDING", self.pending)
        self.patch_account = patch.object(devnull, "ACCOUNT", self.account)
        self.patch_auth_result = patch.object(devnull, "AUTH_RESULT", self.auth_result)
        self.patch_state_dir = patch.object(devnull, "STATE_DIR", root)
        for item in (self.patch_pending, self.patch_account, self.patch_auth_result, self.patch_state_dir):
            item.start()
            self.addCleanup(item.stop)

    def test_callback_rejects_other_scheme_or_state_without_api_call(self):
        with patch.object(devnull, "api") as api:
            for callback in (
                "https://dev-null.sh/omarchy/auth?state=expected&code=abc",
                "devnull://someone-else/auth?state=expected&code=abc",
                "devnull://omarchy/auth?state=wrong&code=abc",
            ):
                with self.subTest(callback=callback), self.assertRaises(devnull.ClientError):
                    devnull.auth_complete(callback)
            api.assert_not_called()
        self.assertTrue(self.pending.exists())
        self.assertFalse(self.auth_result.exists())

    def test_expired_callback_cannot_exchange_code(self):
        self.pending.write_text(json.dumps({
            "state": "expected", "verifier": "private-verifier", "created_at": int(time.time()) - 601
        }), encoding="utf-8")
        with patch.object(devnull, "api") as api, self.assertRaisesRegex(devnull.ClientError, "expired"):
            devnull.auth_complete("devnull://omarchy/auth?state=expected&code=abc")
        api.assert_not_called()

    def test_valid_callback_exchanges_code_once_and_clears_pending(self):
        with patch.object(devnull, "api", return_value={"data": {"username": "tester"}}) as api:
            result = devnull.auth_complete("devnull://omarchy/auth?state=expected&code=abc")
        self.assertEqual(result, {"authenticated": True, "username": "tester"})
        api.assert_called_once_with("POST", "/api/v1/devices", {
            "code": "abc", "code_verifier": "private-verifier"
        })
        self.assertFalse(self.pending.exists())
        self.assertEqual(json.loads(self.account.read_text())["username"], "tester")
        self.assertEqual(devnull.auth_status()["state"], "connected")

    def test_server_error_is_visible_but_wrong_state_is_ignored(self):
        with patch.object(devnull, "api", side_effect=devnull.ClientError("Server rejected approval")):
            with self.assertRaisesRegex(devnull.ClientError, "state"):
                devnull.auth_complete("devnull://omarchy/auth?state=wrong&code=abc")
            self.assertFalse(self.auth_result.exists())
            with self.assertRaisesRegex(devnull.ClientError, "Server rejected"):
                devnull.auth_complete("devnull://omarchy/auth?state=expected&code=abc")
        self.assertEqual(devnull.auth_status(), {"state": "error", "message": "Server rejected approval"})

    def test_private_state_file_is_replaced_with_restricted_permissions(self):
        devnull.write_private(self.account, {"username": "tester"})
        self.assertEqual(self.account.stat().st_mode & 0o777, 0o600)
        devnull.write_private(self.account, {"username": "updated"})
        self.assertEqual(json.loads(self.account.read_text())["username"], "updated")
        self.assertEqual(self.account.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.account.parent.glob("account.json.*")), [])


class RegistrationTests(unittest.TestCase):
    def test_connect_registers_handler_without_installer(self):
        with tempfile.TemporaryDirectory() as home:
            queries = iter(["another.desktop", devnull.DESKTOP_ID])
            calls = []

            def run(command, **kwargs):
                calls.append(command)
                if command[:3] == ["xdg-mime", "query", "default"]:
                    return subprocess.CompletedProcess(command, 0, stdout=next(queries))
                return subprocess.CompletedProcess(command, 0, stdout="")

            with patch.object(devnull.Path, "home", return_value=Path(home)), \
                 patch.object(devnull.shutil, "which", return_value="/usr/bin/tool"), \
                 patch.object(devnull.subprocess, "run", side_effect=run):
                devnull.ensure_callback_handler()
                desktop = Path(home) / ".local/share/applications" / devnull.DESKTOP_ID
                contents = desktop.read_text(encoding="utf-8")
                self.assertIn("auth-complete %u", contents)
                self.assertIn(str(Path(devnull.__file__).resolve()), contents)
                self.assertIn("MimeType=x-scheme-handler/devnull;", contents)
                self.assertIn("NoDisplay=false", contents)
            self.assertIn(["xdg-mime", "default", devnull.DESKTOP_ID, devnull.SCHEME_MIME], calls)


if __name__ == "__main__":
    unittest.main()
