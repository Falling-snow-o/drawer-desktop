# Privacy policy

Drawer Desktop is a local desktop application. It does not include telemetry, analytics or advertising.

## Data stored locally

| Data | Location |
|---|---|
| Settings | `%USERPROFILE%\.boxrun\settings.json` |
| Box registry | `%USERPROFILE%\.boxrun\boxes.json` |
| Tags / aliases | `%USERPROFILE%\.boxrun\tags.json`, `aliases.json` |
| Logs | `%USERPROFILE%\.boxrun\logs\` |
| Crash reports | `%USERPROFILE%\.boxrun\crashes\` |
| Snapshot password (restic) | `%USERPROFILE%\.boxrun\restic.pass` |

Drawer contents live in the directories the user chooses. Uninstalling the application does not delete drawers, logs or settings.

## Network access

The application contacts the network only in these cases:

1. **Update check** – when the user configures an update manifest URL in Settings and clicks "Check for updates", the app reads that manifest and downloads the installer from the URL it contains. The manifest URL is chosen by the user.
2. **Crash upload (optional)** – if the user configures a crash-report URL in Settings, a crash report (plain text: version, OS, stack trace) is POSTed to that URL after an unhandled exception. If no URL is configured, crash reports stay on disk.
3. **Drawer builds** – when the user builds a drawer, WSL downloads an Ubuntu base image and packages from the configured mirror. This traffic comes from WSL/apt, not from the application itself.

No data is sent anywhere by default.

## Third-party components

- Windows Subsystem for Linux and the Ubuntu base image have their own privacy terms.
- Optional `restic` and `zstd` binaries are provided by the user and are not bundled.
- See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Contact

Open an issue in the project repository for privacy questions.
