# Drawer Desktop

Portable WSL2 "drawer" manager for Windows: one folder = one disposable Linux environment, with snapshots, resource limits and a GUI.

![Drawer Desktop](docs/gui.png)

## What it does

- **One folder per environment.** Build, start, stop and delete a Linux environment without touching your main WSL distro.
- **Snapshots with checksums.** Export, verify and restore a drawer before risky changes.
- **Resource limits.** CPU, memory, PID and VRAM caps via cgroup v2 and an optional CUDA shim.
- **GUI + CLI.** The same engine (`box.ps1`) drives both.
- **Extras.** Port discovery, tags/aliases, desktop apps via WSLg, devcontainer/env import, optional restic snapshots.
- **Collaboration (optional).** `data/` can be a git repository; environment differences are tracked as package manifests.

## Requirements

- Windows 10 21H2+ or Windows 11, with WSL2 enabled
- [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0/runtime)

## Install

1. Download `drawer-setup.exe` from the Releases page.
2. Run it. The installer supports `--quiet`, `--dir <path>`, `--uninstall` and `--rollback`.
3. If the build is self-signed, run `signing/Trust-DevCert.ps1` once to trust the publisher certificate.

## Quick start

```powershell
box.ps1 add D:\work\demo
box.ps1 build demo
box.ps1 up demo
box.ps1 exec demo bash
box.ps1 snap demo before-upgrade
box.ps1 snap-restore demo before-upgrade
box.ps1 down demo
```

Or use the GUI: **Add → Start → Snapshot → Ports → Desktop**.

## Build from source

```powershell
git clone <repo>
cd <repo>
powershell -File 打包.ps1 -Version 1.0.0
```

Output: `dist\drawer-setup.exe` and `dist\latest.json`.

Tests (Windows with WSL2):

```powershell
powershell -File test\ci.ps1            # syntax + build
powershell -File test\smoke.ps1         # engine, 13 checks
powershell -File test\collab-smoke.ps1  # collaboration, 21 checks
powershell -File test\gui-smoke.ps1     # installed GUI, 26 checks
```

## Code signing policy

**Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).**

- Committers and reviewers: `<GitHub team or maintainer list>`
- Approvers: `<GitHub owners>`

Builds submitted for signing are produced by the GitHub Actions workflow in this repository from tagged source. Every signing request is manually approved by a project approver.

See [CODE_SIGNING_POLICY.md](CODE_SIGNING_POLICY.md) for details.

## Privacy

The app does not collect telemetry. It only contacts the network when the user configures an update URL, checks for updates, or configures an optional crash-report URL.

See [PRIVACY.md](PRIVACY.md).

## License

MIT. See [LICENSE](LICENSE) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Security model and boundaries: [SECURITY.md](SECURITY.md). Collaboration model: [COLLAB.md](COLLAB.md).
