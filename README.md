<div align="center">

# AEGIS

**One command. Every runtime. Game ready.**

![README visits](https://count.getloli.com/@marek-codex.aegis?theme=booru-lewd)

[![Validation](https://github.com/Marek-Codex/AEGIS/actions/workflows/validate.yml/badge.svg)](https://github.com/Marek-Codex/AEGIS/actions/workflows/validate.yml)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-3CA0FF?style=flat-square&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-07111C?style=flat-square&logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-A03CFF?style=flat-square)

**Automated Essentials for Gaming Installation System**

</div>

AEGIS prepares a clean Windows installation for gaming. It installs the
runtimes older and newer games expect, repairs WinGet when necessary, and shows
the exact plan before changing anything.

No debloat presets, registry folklore, launchers, browsers, or mystery tweaks.

## Run it

Open Windows PowerShell and paste:

```powershell
irm https://github.com/Marek-Codex/AEGIS/raw/refs/heads/main/Install.ps1 |
  % { $_.TrimStart([char]0xFEFF) } | iex
```

Or download [`Install.bat`](Install.bat). If `Install.ps1` is beside it, the BAT
uses that copy. Otherwise, it downloads the current script to a temporary
folder and runs it.

AEGIS supports Windows PowerShell 5.1 and PowerShell 7 on Windows 10 and 11.
Installation asks for administrator access once. Help, package listing, and dry
runs do not require elevation.

> Review remote scripts before running them. For a fixed, reproducible build,
> use a versioned download from the
> [latest release](https://github.com/Marek-Codex/AEGIS/releases/latest).

## Recommended stack

The recommended profile installs 40 items on x64 Windows:

- Visual C++ 2005, 2008, 2010, 2012, 2013, and current v14, including x86
- .NET Desktop Runtime 3.1, 5, 6, 7, 8, 9, and 10
- ASP.NET Core Runtime 2.1, 3.1, 5, 6, 7, 8, 9, and 10
- DirectX, XNA, OpenAL, WebView2, PhysX, PhysX Legacy, and DirectPlay
- NanaZip and current PowerShell
- Amazon Corretto 25 JDK

Arm64 systems receive native packages where they are available. AEGIS installs
x86 VC++ components on 64-bit Windows because 32-bit games still need them.

Each component family runs on its own progress screen. The final screen lists
every item as installed, current, planned, or failed and provides the full log
path. AEGIS never restarts Windows automatically.

## Optional Workbench

Customize includes a disabled-by-default Power User Workbench:

- UniGetUI
- Everything Beta
- VLC Nightly
- Xtreme Download Manager from the Microsoft Store
- Sublime Text 4
- Visual Studio Code Insiders
- WizTree

Prerelease applications are labeled in the installation plan and are never
part of Recommended.

## Useful commands

```powershell
# Preview the recommended stack without changing Windows
.\Install.ps1 -Profile Recommended -DryRun -Unattended

# Install the recommended stack from an elevated shell
.\Install.ps1 -Profile Recommended -Unattended

# Install selected component families
.\Install.ps1 -Profile Custom -IncludeGroup VC++,DotNet,AspNet -Unattended

# Install only the optional Workbench
.\Install.ps1 -Profile Custom -IncludeGroup Workbench -Unattended

# Show the complete manifest
.\Install.ps1 -ListPackages
```

`Modern`, `Legacy`, and `Full` remain accepted as aliases for `Recommended`.
Exit code `0` means success, `1` means a fatal setup error, and `2` means one or
more selected items failed.

## Releases

Each release includes a version-pinned BAT, ZIP, `tar.gz`, gzip-compressed
PowerShell source, and `SHA256SUMS.txt`. GitHub also generates its standard
source ZIP and source tarball.

WinGet verifies installer hashes against its manifests. AEGIS uses exact
package IDs and explicit WinGet or Microsoft Store sources, retries packages
independently, and writes its log under `%TEMP%` unless `-LogPath` is supplied.

## Credit

Conceptually inspired by
[PC-Gaming-Redists](https://github.com/harryeffinpotter/PC-Gaming-Redists) by
[`@harryeffinpotter`](https://github.com/harryeffinpotter).

AEGIS is an independent clean-room implementation and shares no source code
with PC-Gaming-Redists. Released under the [MIT License](LICENSE).
