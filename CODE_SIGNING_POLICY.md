# Code signing policy

**Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).**

## Scope

Only release artifacts built from this repository by the project's GitHub Actions workflow are signed:

- `Drawer.exe` (main application)
- `drawer-setup.exe` (installer)

No third-party binaries are signed by this project. Third-party components are listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Roles

| Role | Members |
|---|---|
| Authors / committers | `[Falling-snow-o](https://github.com/Falling-snow-o)` |
| Reviewers | `[Falling-snow-o](https://github.com/Falling-snow-o)` |
| Approvers | `[Falling-snow-o](https://github.com/Falling-snow-o)` |

For a single-maintainer project, the maintainer holds all roles. Changes from outside contributors require review before merge.

> Replace the placeholders above with the actual GitHub team/user links when the public repository is created.

## Build and signing process

1. A release is triggered manually through the `release-sign` GitHub Actions workflow with a version input.
2. The workflow builds the installer from source on a clean Windows runner (`打包.ps1 -SkipTest -Version <version>`).
3. The unsigned artifact is uploaded and submitted to SignPath for origin verification.
4. A project approver reviews and approves the signing request in SignPath.
5. The signed artifact is attached to the GitHub Release.

Local builds are signed only with a self-signed development certificate (`signing/New-DevCert.ps1`) and are not published as releases.

## Privacy

See [PRIVACY.md](PRIVACY.md). The application does not transfer data to other systems unless the user configures an update URL or a crash-report URL.

## Uninstallation

The installer registers an uninstall entry and also supports:

```powershell
drawer-setup.exe --uninstall --quiet
```
