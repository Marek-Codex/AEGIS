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

AEGIS installs the complete curated prerequisite stack for Windows gaming:
Visual C++ redistributables, .NET Desktop and ASP.NET Core runtimes, legacy
gaming components, and a few deliberate essentials. It is built for a clean
Windows installation but is safe to run again later.

No debloat rituals, registry folklore, launchers, browsers, chat clients, or
monitoring suites. Choose the recommended installation or customize the
runtime categories before anything changes. An optional Power User Workbench
is kept separate from the prerequisite baseline.

> AEGIS is under active development. Review the installation plan before using
> it on a production system.

## Run AEGIS

Open Windows PowerShell and run:

```powershell
irm https://github.com/Marek-Codex/AEGIS/raw/refs/heads/main/Install.ps1 |
  % { $_.TrimStart([char]0xFEFF) } | iex
```

The `TrimStart` guard makes the command tolerant of a stray UTF-8 byte-order
mark introduced by an HTTP client, proxy, or cache. Do not run remote scripts
you have not inspected. Pin the URL to a release tag or commit SHA for
reproducible deployments.

Alternatively, download and run [`Install.bat`](Install.bat), or run the
PowerShell file directly:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install.ps1
```

Versioned downloads are available under [Releases](../../releases). Each
release includes a standalone tag-pinned BAT, a ZIP, a `tar.gz`, gzip-compressed
PowerShell source, and a SHA-256 checksum manifest. GitHub also provides its
standard source ZIP and source tarball.

## What the recommended installation includes

### Visual C++

- Microsoft Visual C++ 2005, 2008, 2010, 2012, 2013, and current v14
- Both x86 and x64 on x64 Windows because 32-bit games still require x86
- Native Arm64 v14 support on Arm64 Windows

### .NET Desktop

- Every non-preview Windows Desktop runtime family currently published in
  WinGet: 3.1, 5, 6, 7, 8, 9, and 10
- Available x86 variants are included alongside native 64-bit variants

### ASP.NET Core

- Runtime packages for 2.1, 3.1, 5, 6, 7, 8, 9, and 10
- Old similarly named packages that WinGet identifies as SDKs are excluded

### Gaming compatibility

- DirectX End-User Runtime
- Microsoft XNA Framework Redistributable
- OpenAL
- Microsoft Edge WebView2 Runtime
- NVIDIA PhysX and PhysX Legacy
- DirectPlay Windows feature

### Essentials

- NanaZip, replacing 7-Zip
- Current PowerShell, supplementing the inbox Windows PowerShell 5.1

Amazon Corretto 25 JDK is included in the recommended stack and can be disabled
through Customize.

## How it works

```text
Launch AEGIS
  -> Install recommended / Customize / Exit
  -> Review the exact installation plan
  -> Repair or update WinGet when needed
  -> Install each selected prerequisite independently
  -> Show a complete result summary and save the full log
```

The recommended path installs everything above. Customize exposes seven broad
components: `VC++`, `DotNet`, `AspNet`, `Gaming`, `Essentials`, `Java`, and
`Workbench`.

The optional Workbench installs UniGetUI, Everything Beta, VLC Nightly, Xtreme
Download Manager from the Microsoft Store, Sublime Text 4, and Visual Studio
Code Insiders, plus WizTree. Prerelease applications are labeled clearly and
are never part of Recommended.

## Automation and previews

```powershell
# Preview the recommended stack without changing Windows
.\Install.ps1 -Profile Recommended -DryRun -Unattended

# Install the recommended stack non-interactively (elevate the shell first)
.\Install.ps1 -Profile Recommended -Unattended

# Install selected components only
.\Install.ps1 -Profile Custom -IncludeGroup VC++,DotNet,AspNet -Unattended

# Install the optional Power User Workbench
.\Install.ps1 -Profile Custom -IncludeGroup Workbench -Unattended

# List every package in the manifest
.\Install.ps1 -ListPackages
```

The former `Modern`, `Legacy`, and `Full` profile names remain accepted as
compatibility aliases for `Recommended`.

## Safety and behavior

- `-DryRun` performs no installation, WinGet update, or Windows feature change.
- WinGet verifies downloaded installer hashes against its manifests.
- Exact package IDs and explicit WinGet or Microsoft Store sources are used.
- Every package is retried and reported independently.
- Logs are written to `%TEMP%` unless `-LogPath` is supplied.
- Fatal and partial failures return nonzero exit codes.
- Installation requests administrator access once at launch. Unattended runs
  should start in an elevated shell; help, package listing, and dry runs do not
  require elevation.
- AEGIS never restarts Windows automatically.
- Installed/current state is determined from WinGet exit codes rather than
  localized output text.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | Completed successfully |
| `1` | Fatal bootstrap or configuration error |
| `2` | One or more selected items failed |

## Architecture

```text
Install.bat        Standalone bootstrap and local-script entry point
Install.ps1        Menu, manifest, WinGet bootstrap, and install engine
tests/             Non-destructive validation
.github/workflows  Windows PowerShell, PowerShell 7, and release automation
```

## Credit

Conceptually inspired by
[PC-Gaming-Redists](https://github.com/harryeffinpotter/PC-Gaming-Redists) by
[`@harryeffinpotter`](https://github.com/harryeffinpotter).

AEGIS is an independent clean-room implementation. It shares no source code
with PC-Gaming-Redists.
