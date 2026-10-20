# Contributing

Thanks for helping improve dev/null Log. Please open an issue before making a large behavior or UI change so the scope is clear.

## Layout

- `BarWidget.qml` contains the bar button, panel, theme bindings, and UI state.
- `Model.js` contains pure functions for usernames and the public commit feed.
- `devnull.py` handles user-level callback registration, device authorization, and signed account reads. It prints one JSON object per invocation for the QML process to consume.
- `manifest.json` declares the Omarchy widget and its settings.
- `install.sh` is for a local checkout. Normal Git installs use `omarchy plugin add` and do not run it.

## Checks

Use Python 3.10 or newer and Node 20 or newer. On Omarchy, run:

```bash
python3 -m unittest discover -s tests -v
node tests/model.test.mjs
bash -n install.sh
omarchy plugin validate .
```

The Python tests use temporary directories and mocked API calls. Never add a real device key, callback URL, account response, or notification payload from your account to the repository or an issue. Test UI changes with both a light and a dark Omarchy theme and with long notification text.

Keep account API operations confined to `devnull.py` and render remote text as plain text in QML. If a change adds a write action, explain it in the UI and update the security section in `README.md`.
