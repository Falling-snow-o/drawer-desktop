# Code signing policy

Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).

## What gets signed

Only release artifacts built from this repository by GitHub Actions:

- `Drawer.exe`
- `drawer-setup.exe`

No third-party binaries are signed. Third-party components are listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Roles

| Role | Member |
|---|---|
| Author / committer | [Falling-snow-o](https://github.com/Falling-snow-o) |
| Reviewer | [Falling-snow-o](https://github.com/Falling-snow-o) |
| Approver | [Falling-snow-o](https://github.com/Falling-snow-o) |

Single-maintainer project. External pull requests require review before merge.

## Build and signing

1. A release is started manually with the `release-sign` workflow and a version input.
2. The workflow builds the installer from source on a Windows runner (`打包.ps1 -SkipTest -Version <version>`).
3. The unsigned artifact is submitted to SignPath for origin verification.
4. An approver reviews and approves the request.
5. The signed artifact is attached to the GitHub Release.

Local builds use a self-signed certificate (`signing/New-DevCert.ps1`) and are not published as releases.

## Privacy

See [PRIVACY.md](PRIVACY.md). The app sends no data unless the user configures an update URL or crash-report URL.

## Uninstall

The installer registers an uninstall entry, and also supports:

```powershell
drawer-setup.exe --uninstall --quiet
```
