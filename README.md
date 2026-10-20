# dev/null Log for Omarchy

A theme-aware Omarchy bar widget for [dev/null](https://dev-null.sh). It shows recent public commits from selected developers and, after optional account approval, your notifications and unread count.

The panel follows the dev/null log's compact timeline style while using the active Omarchy theme's colors and fonts. Theme changes apply automatically.

## Install

On Omarchy 4 with the Quickshell plugin host, install from this repository's Git URL:

```bash
omarchy plugin add https://github.com/Eljakani/dev-null-omarchy-plugin.git --enable
```

The widget works without an account for public commits. Open its **Notifications** tab and choose **Connect your dev/null account** to enable your inbox. Review the device approval page in your browser. If prompted to open a `devnull://` link, choose **Omarchy dev/null authorization**. The widget detects the result automatically.

The Connect action registers a user-level desktop handler for `devnull://`; Omarchy does not run install scripts when adding a plugin. This may replace another app's default handler for that URL scheme. It can be changed later in your desktop's default-app settings.

For a local checkout instead of a Git URL, run `bash install.sh` from the checkout. This copies the plugin into `~/.config/omarchy/plugins/devnull.log/` and enables it. It does not need elevated privileges.

## Use

- **Log** combines and sorts recent public commits from up to five developers. Set comma-separated handles in the widget's **Usernames** setting or in its `usernames` value in `~/.config/omarchy/shell.json`. The defaults are `nunomaduro,brendt,paulinevos`.
- **Notifications** loads your inbox only when you open that tab. The dev/null API marks notifications as read when fetched. The unread badge is checked periodically without opening the inbox.
- Select a commit or notification to open it on dev/null. Middle click refreshes; right click opens the full trending log.
- Keyboard: `j`/`k` or arrows to select, `Enter` to open, `i` to switch tabs, `r` to refresh, `o` for the full log, `Esc` to close.

The widget refreshes public commits when opened if stale, and every five minutes while open. Account status is checked every minute.

## Requirements

Omarchy 4 with the Quickshell plugin host, Python 3.10 or newer, `curl`, OpenSSH (`ssh-keygen`), and `xdg-mime` on `PATH`. These are checked when you connect. `update-desktop-database` is used if available.

## Update and remove

For a Git install, run `omarchy plugin update devnull.log`. For a local checkout, rerun `bash install.sh` after pulling new files.

Run `omarchy plugin remove devnull.log` to remove the widget. If you connected your account, also revoke **Omarchy dev/null Log** under dev/null **Settings → Devices**. Removing the plugin or local key does not revoke the device on dev/null. After revoking, you may delete `~/.local/share/devnull-omarchy/` and `~/.local/share/applications/devnull-omarchy-auth.desktop`, then reset your default `devnull://` handler if needed.

## Security and privacy

The plugin creates a dedicated Ed25519 device key at `~/.local/share/devnull-omarchy/device_key` (`0600`) inside a `0700` directory. It does not use your GitHub SSH key or browser cookies. The authorization verifier and callback result stay in that same directory. Account API requests go only to `https://dev-null.sh` with TLS verification. Commit and notification text is displayed as plain text. The plugin currently reads account information; it does not post, star, or change settings.

The approved device key is an account credential. The dev/null device API may grant more account capability than this widget uses. Keep the key private and revoke the device if your computer or key is compromised. The plugin has not had an independent security audit.

## Development

Run the release checks with:

```bash
python3 -m unittest discover -s tests -v
node tests/model.test.mjs
omarchy plugin validate .
```

The plugin is licensed under MIT; see [LICENSE](LICENSE).
