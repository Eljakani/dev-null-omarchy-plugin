#!/usr/bin/env python3
"""Local device authorization and signed read requests for the Omarchy widget."""

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse


ORIGIN = "https://dev-null.sh"
REDIRECT = "devnull://omarchy/auth"
STATE_DIR = Path.home() / ".local" / "share" / "devnull-omarchy"
KEY = STATE_DIR / "device_key"
PENDING = STATE_DIR / "pending.json"
ACCOUNT = STATE_DIR / "account.json"
AUTH_RESULT = STATE_DIR / "last_auth_result.json"
DESKTOP_ID = "devnull-omarchy-auth.desktop"
SCHEME_MIME = "x-scheme-handler/devnull"


class ClientError(Exception):
    pass


def write_private(path: Path, value: dict) -> None:
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(STATE_DIR, 0o700)
    fd, name = tempfile.mkstemp(prefix=path.name + ".", dir=STATE_DIR)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            json.dump(value, file)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def read_private(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ClientError("Authorization setup is missing. Connect again.") from exc


def ensure_key() -> str:
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(STATE_DIR, 0o700)
    if not KEY.exists():
        subprocess.run(
            ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "devnull-omarchy", "-f", str(KEY)],
            check=True, capture_output=True,
        )
    os.chmod(KEY, 0o600)
    output = subprocess.run(
        ["ssh-keygen", "-lf", str(KEY) + ".pub", "-E", "sha256"],
        check=True, capture_output=True, text=True,
    ).stdout
    match = re.search(r"SHA256:[A-Za-z0-9+/]{43}", output)
    if not match:
        raise ClientError("Could not read the device key fingerprint.")
    return match.group(0)


def desktop_exec_quote(value: str) -> str:
    if "\n" in value or "\r" in value:
        raise ClientError("Plugin path cannot contain a newline.")
    return ('"' + value.replace("\\", "\\\\").replace('"', '\\"')
            .replace("$", "\\$").replace("`", "\\`").replace("%", "%%") + '"')


def ensure_callback_handler() -> None:
    """Register the callback when Connect is clicked, including Git installs."""
    if not shutil.which("xdg-mime"):
        raise ClientError("xdg-mime is required to connect your account.")
    applications = Path.home() / ".local" / "share" / "applications"
    applications.mkdir(mode=0o755, parents=True, exist_ok=True)
    desktop = applications / DESKTOP_ID
    executable = desktop_exec_quote(sys.executable)
    helper = desktop_exec_quote(str(Path(__file__).resolve()))
    contents = ("[Desktop Entry]\n"
                "Type=Application\n"
                "Name=Omarchy dev/null authorization\n"
                f"Exec={executable} {helper} auth-complete %u\n"
                f"MimeType={SCHEME_MIME};\n"
                "NoDisplay=false\n"
                "Terminal=false\n")
    if not desktop.exists() or desktop.read_text(encoding="utf-8") != contents:
        desktop.write_text(contents, encoding="utf-8")
        desktop.chmod(0o644)
        if shutil.which("update-desktop-database"):
            subprocess.run(["update-desktop-database", str(applications)],
                           capture_output=True)
    current = subprocess.run(["xdg-mime", "query", "default", SCHEME_MIME],
                             check=True, capture_output=True, text=True).stdout.strip()
    if current != DESKTOP_ID:
        subprocess.run(["xdg-mime", "default", DESKTOP_ID, SCHEME_MIME],
                       check=True, capture_output=True)
        current = subprocess.run(["xdg-mime", "query", "default", SCHEME_MIME],
                                 check=True, capture_output=True, text=True).stdout.strip()
        if current != DESKTOP_ID:
            raise ClientError("Could not register the devnull:// callback handler.")


def auth_start() -> dict:
    for dependency in ("curl", "ssh-keygen"):
        if not shutil.which(dependency):
            raise ClientError(f"{dependency} is required to connect your account.")
    ensure_callback_handler()
    fingerprint = ensure_key()
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    state = secrets.token_urlsafe(24)
    AUTH_RESULT.unlink(missing_ok=True)
    write_private(PENDING, {"verifier": verifier, "state": state, "created_at": int(time.time())})
    query = urllib.parse.urlencode({
        "fingerprint": fingerprint,
        "device_name": "Omarchy dev/null Log",
        "code_challenge": challenge,
        "code_challenge_method": "S256",
        "state": state,
        "redirect_uri": REDIRECT,
    })
    return {"url": ORIGIN + "/mobile/authorize?" + query}


def auth_status() -> dict:
    if AUTH_RESULT.exists():
        result = read_private(AUTH_RESULT)
        if result.get("authenticated") is True:
            return {"state": "connected", "username": result.get("username", "")}
        if result.get("error"):
            return {"state": "error", "message": result["error"]}
    if PENDING.exists():
        pending = read_private(PENDING)
        if int(time.time()) - int(pending.get("created_at", 0)) <= 600:
            return {"state": "waiting"}
        return {"state": "error", "message": "Approval link expired. Try connecting again."}
    return {"state": "idle"}


def signature(message: bytes) -> str:
    try:
        result = subprocess.run(
            ["ssh-keygen", "-Y", "sign", "-n", "devnull-api", "-f", str(KEY)],
            input=message, capture_output=True, check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise ClientError("Could not sign the API request with the device key.") from exc
    lines = result.stdout.decode("ascii").splitlines()
    encoded = "".join(line for line in lines if line and not line.startswith("-----"))
    if not encoded:
        raise ClientError("Could not sign the API request.")
    return encoded


def api(method: str, path: str, body: dict | None = None) -> dict:
    if not KEY.exists():
        raise ClientError("Connect your dev/null account first.")
    data = b"" if body is None else json.dumps(body, separators=(",", ":")).encode("utf-8")
    timestamp = str(int(time.time()))
    nonce = secrets.token_hex(16)
    message = b"\n".join([timestamp.encode(), nonce.encode(), method.encode(), path.encode(), data])
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-Devnull-Timestamp": timestamp,
        "X-Devnull-Nonce": nonce,
        "X-SSH-Signature": signature(message),
    }
    try:
        command = ["curl", "--disable", "--proto", "=https", "--silent", "--show-error",
                   "--max-time", "10", "--request", method]
        for name, value in headers.items():
            command += ["--header", f"{name}: {value}"]
        if body is not None:
            command += ["--data-binary", "@-"]
        command += ["--write-out", "\n%{http_code}", ORIGIN + path]
        result = subprocess.run(command, input=data, capture_output=True, check=True)
        payload, status_text = result.stdout.rsplit(b"\n", 1)
        status = int(status_text)
        response = json.loads(payload)
    except (subprocess.CalledProcessError, ValueError, json.JSONDecodeError) as exc:
        raise ClientError("Could not read a response from dev/null.") from exc
    if status >= 400:
        api_code = response.get("code", "")
        if api_code == "device_not_approved":
            raise ClientError("Device is not approved. Connect your account again.")
        if api_code == "invalid_grant":
            raise ClientError("Approval expired or was already used. Connect again.")
        if api_code == "invalid_signature":
            raise ClientError("Device signature was rejected. Check your clock and try again.")
        if api_code == "rate_limited":
            raise ClientError("Too many connection attempts. Wait a minute, then try again.")
        raise ClientError(f"dev/null returned HTTP {status} ({api_code or 'unknown error'}).")
    return response


def auth_complete(callback: str) -> dict:
    parsed = urllib.parse.urlparse(callback)
    if (parsed.scheme, parsed.netloc, parsed.path) != ("devnull", "omarchy", "/auth"):
        raise ClientError("Unexpected authorization callback.")
    query = urllib.parse.parse_qs(parsed.query)
    pending = read_private(PENDING)
    if int(time.time()) - int(pending.get("created_at", 0)) > 600:
        raise ClientError("Authorization expired. Connect again.")
    if not secrets.compare_digest(query.get("state", [""])[0], pending["state"]):
        raise ClientError("Authorization state did not match.")
    if query.get("error"):
        write_private(AUTH_RESULT, {"error": "Authorization was cancelled."})
        raise ClientError("Authorization was cancelled.")
    code = query.get("code", [""])[0]
    if not code:
        raise ClientError("Authorization code was missing.")
    try:
        response = api("POST", "/api/v1/devices", {"code": code, "code_verifier": pending["verifier"]})
    except ClientError as exc:
        write_private(AUTH_RESULT, {"error": str(exc)})
        raise
    PENDING.unlink(missing_ok=True)
    user = response.get("data", {})
    write_private(ACCOUNT, {"username": user.get("username", "")})
    result = {"authenticated": True, "username": user.get("username", "")}
    write_private(AUTH_RESULT, result)
    return result


def me() -> dict:
    if not KEY.exists():
        return {"authenticated": False, "unread": 0}
    try:
        response = api("GET", "/api/v1/me")
    except ClientError as exc:
        return {"authenticated": False, "unread": 0, "error": str(exc)}
    user = response.get("data", {})
    return {
        "authenticated": True,
        "username": user.get("username", ""),
        "unread": int(response.get("unread_notifications_count", 0)),
    }


def notifications() -> dict:
    response = api("GET", "/api/v1/notifications")
    items = []
    labels = {
        "followed": "followed you",
        "starred": "starred your commit",
        "replied": "replied to your commit",
        "quoted": "quoted your commit",
        "mentioned": "mentioned you",
        "approved": "Your commit was approved",
        "rejected": "Your commit was rejected",
        "leveled_up": "You leveled up",
    }
    for item in response.get("data", [])[:20]:
        kind = str(item.get("type", ""))
        actor = item.get("actor") or {}
        username = str(actor.get("username", ""))
        title = labels.get(kind, kind.replace("_", " "))
        if username and kind not in ("approved", "rejected", "leveled_up"):
            title = "@" + username + " " + title
        count = int(item.get("event_count", 1) or 1)
        if count > 1:
            title += f" (+{count - 1})"
        commit = item.get("commit") or {}
        group_id = str(item.get("id", ""))
        items.append({
            "id": group_id,
            "kind": kind,
            "title": title,
            "body": str(commit.get("body", "")) or str(item.get("reason", "") or ""),
            "createdAt": str(item.get("created_at", "")),
            "url": ORIGIN + "/notifications/" + urllib.parse.quote(group_id, safe="") + "/group",
        })
    return {"notifications": items}


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if command == "auth-start":
            result = auth_start()
        elif command == "auth-complete":
            result = auth_complete(sys.argv[2])
        elif command == "auth-status":
            result = auth_status()
        elif command == "me":
            result = me()
        elif command == "notifications":
            result = notifications()
        else:
            raise ClientError("Unknown command.")
    except (IndexError, ClientError, OSError, subprocess.CalledProcessError, ValueError) as exc:
        result = {"error": str(exc)}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if "error" not in result else 1


if __name__ == "__main__":
    raise SystemExit(main())
