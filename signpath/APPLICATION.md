# SignPath Foundation application — draft answers

Fill in the bracketed values, paste into <https://signpath.org/apply>, and keep this file updated.

## Project

| Field | Value |
|---|---|
| Project name | Drawer Desktop |
| One-line description | Portable WSL2 drawer manager for Windows: disposable Linux environments with snapshots, resource limits and a GUI. |
| Repository URL | `https://github.com/Falling-snow-o/drawer-desktop` |
| License | MIT (OSI-approved) |
| Website / download page | `https://github.com/Falling-snow-o/drawer-desktop/releases` |
| Language / stack | C# (.NET 8, WPF) + PowerShell engine |
| Current release | `v<version>` (installer attached to GitHub Releases) |
| Maintainer | `<name / GitHub handle>` |
| Contact | `<email>` |
| MFA enabled on GitHub and will be enabled on SignPath | Yes |

## What gets signed

| Artifact | Built by | Notes |
|---|---|---|
| `drawer-setup.exe` | GitHub Actions `release-sign` workflow | Self-contained installer (framework-dependent) |
| `Drawer.exe` | same workflow, inside the installer payload | Main WPF application |

No third-party binaries are signed. The app downloads Ubuntu/WSL components at the user's request; they are not bundled.

## Build reproducibility

- Workflow: `.github/workflows/release-sign.yml`
- Command: `./打包.ps1 -SkipTest -Version <version>`
- Runner: `windows-latest`, .NET SDK 8.0.x
- Output: `dist/drawer-setup.exe` + `dist/latest.json`
- SHA256 is printed in the workflow log before the signing request

## Code signing policy

Hosted at `CODE_SIGNING_POLICY.md` and linked from `README.md` and `README.en.md`.

Contains the required sentence:

> Free code signing provided by SignPath.io, certificate by SignPath Foundation.

Roles (single-maintainer project):

- Authors / committers: `Falling-snow-o`
- Reviewers: `Falling-snow-o` (external PRs require review)
- Approvers: `Falling-snow-o`

## Privacy

`PRIVACY.md` documents that the app has no telemetry and only uses the network when the user configures an update URL or crash-report URL, or when WSL builds a drawer.

## Why signing helps

Drawer Desktop is distributed as a portable installer outside the Microsoft Store. Without a trusted signature, users see "Unknown publisher" and SmartScreen warnings. The installer also updates itself, so users need to verify that update binaries come from this project.

## Uninstallation

`drawer-setup.exe --uninstall` and the Windows "Apps" list. Drawers and user data are intentionally kept; this is documented.

## Anything unusual

- The app manages WSL2 distributions and can export/import them. It does not bundle or redistribute Ubuntu images; WSL downloads them.
- The app can optionally write a start-menu shortcut for desktop apps inside a drawer.

## Checklist before submitting

- [ ] Repository is public and contains `LICENSE` (MIT)
- [ ] `README.en.md`, `CODE_SIGNING_POLICY.md`, `PRIVACY.md` are committed
- [ ] At least one public release with the installer exists
- [ ] `release-sign.yml` builds successfully on GitHub Actions
- [ ] Maintainer has MFA enabled
- [ ] No proprietary components in the signed artifacts
