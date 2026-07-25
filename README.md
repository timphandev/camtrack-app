# camtrack

Camera monitoring app: polls your IP cameras, NVRs, and other network devices for reachability
and alerts you by email or Telegram when one goes offline. Single binary, web UI included, runs
on Linux (amd64/arm64).

## Install

```bash
curl -sfL https://raw.githubusercontent.com/timphandev/camtrack-app/main/install.sh | sudo sh
```

Detects your package manager (apt or dnf/yum) and CPU architecture, downloads the matching
`.deb`/`.rpm` from the latest release, and installs it. camtrack runs as a systemd service
(`camtrack`), starting automatically on boot.

```bash
systemctl status camtrack     # check it's running
sudo systemctl restart camtrack
```

### Manual install

Prefer to manage it yourself? Every release also includes plain binaries
(`camtrack-<version>-<os>-<arch>`) with a `.sha256` checksum, no installer or service
registration attached.

## Using it

Once installed, open the web UI:

```
http://localhost:2706
```

(Port may differ if changed — see Configuration.) From there you can add cameras, NVRs, and other
network devices, set up email and/or Telegram alerts, choose who gets notified and when (and
scope recipients to specific devices), and customize the alert templates per channel.

## Configuration

Most settings (SMTP, Telegram bot token, polling interval, offline-alert timing, notification
recipients, alert templates) are configured from the web UI — no restart needed.

Data (SQLite database) is stored at `/var/lib/camtrack`.

## Upgrading

Re-run the install command — installing a newer version over an existing one upgrades in place
and preserves your data. The app also checks for updates itself on a schedule (configurable from
the web UI's Update page) and can apply them automatically if you turn that on.

## Uninstalling

`sudo apt remove camtrack` or `sudo dnf remove camtrack` stops and disables the service but
leaves `/var/lib/camtrack` (your data) in place. On Debian/Ubuntu, `sudo apt purge camtrack`
additionally deletes `/var/lib/camtrack` and the `camtrack` system user — use this if you want a
clean removal with no data left behind.

## Support

Found a bug or have a feature request? [Open an issue](https://github.com/timphandev/camtrack-app/issues).
