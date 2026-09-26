<div align="center">

# AEGIS

**One command. The runtimes games expect.**

![README visits](https://count.getloli.com/@marek-codex.aegis?theme=booru-lewd)

[![Validation](https://github.com/Marek-Codex/AEGIS/actions/workflows/validate.yml/badge.svg)](https://github.com/Marek-Codex/AEGIS/actions/workflows/validate.yml)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-3CA0FF?style=flat-square&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-07111C?style=flat-square&logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-A03CFF?style=flat-square)

**Automated Essentials for Gaming Installation System**

</div>

AEGIS sets up Windows with the shared runtimes many PC games expect. It checks
what is already installed, repairs WinGet when needed, and shows you the plan
before making changes.

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

## The menu

Running AEGIS without arguments opens a keyboard-driven menu with three
choices:

| Choice | What it does |
| --- | --- |
| **1  Install recommended** | The curated runtime stack described below |
| **2  Customize runtimes** | Start from Recommended, then toggle whole families or expand one to pick individual versions |
| **3  Workbench apps** | Optional desktop tools, kept separate from the runtime stack |

Use the arrow keys (or W/S) and Enter, or press the number to jump straight to
a choice. In Customize, Space toggles, Right/Left shows or hides the versions in
a family, and A/N select all or none. Every path ends on a one-screen plan
where Enter installs and Esc goes back.

AEGIS supports Windows PowerShell 5.1 and PowerShell 7 on Windows 10 and 11.
Installation asks for administrator access once. Help, package listing, and dry
runs do not require elevation.

> Review remote scripts before running them. For a fixed, reproducible build,
> use a versioned download from the
> [latest release](https://github.com/Marek-Codex/AEGIS/releases/latest).

## Recommended stack

Recommended installs 40 items on x64 Windows. It covers common game runtimes
and includes Corretto 25 as the default system JDK:

- Visual C++ 2005, 2008, 2010, 2012, 2013, and current v14, including x86
- .NET Desktop Runtime 3.1, 5, 6, 7, 8, 9, and 10
- ASP.NET Core Runtime 2.1, 3.1, 5, 6, 7, 8, 9, and 10
- DirectX, XNA, OpenAL, WebView2, PhysX, PhysX Legacy, and DirectPlay
- NanaZip and current PowerShell
- Amazon Corretto 25 JDK

### Optional compatibility components

Customize can also install Corretto 21, 17, or 8 for applications that need a
specific Java version. Minecraft's official launcher normally manages Java for
you. If you use another launcher, Java 21 is used by Minecraft 1.20.5–1.21.11,
Java 17 by 1.18–1.20.4, and some older versions or modpacks need Java 8. These
versions are optional because installing several JDKs can make the default
`java` command unclear.

The optional **Legacy** component enables .NET Framework 3.5, which also
provides .NET Framework 2.0 and 3.0 for older games and applications. Windows
may download the feature files through Windows Update.

Anti-cheat software is installed by the game that needs it. Graphics drivers
provide the Vulkan runtime, so AEGIS does not install a separate Vulkan package.

Arm64 systems receive native packages where they are available. AEGIS installs
x86 VC++ components on 64-bit Windows because 32-bit games still need them.

While it runs, AEGIS prints one line per package with its status and how long
it took, and shows progress in the window title. The final screen sums up each
family, lists anything that failed along with the reason, and gives the full
log path; press L to open the log. AEGIS never restarts Windows automatically.

## Optional Workbench

**Workbench apps** in the main menu (or `-IncludeGroup Workbench`) offers a
separate set of desktop tools. They are never part of Recommended or Customize:

- UniGetUI
- Everything Beta
- VLC Nightly
- Xtreme Download Manager from the Microsoft Store
- Sublime Text 4
- Visual Studio Code Insiders
- WizTree

Prerelease applications are labeled `[PRE-RELEASE]` in the picker and the plan.

## Choose components

Use **Customize runtimes** in the menu, or select components directly from the
command line:

| Component | Includes |
| --- | --- |
| `VC++` | Visual C++ redistributables for x86 and your system architecture |
| `DotNet` | .NET Desktop runtimes |
| `AspNet` | ASP.NET Core runtimes |
| `Gaming` | DirectX, XNA, OpenAL, WebView2, PhysX, and DirectPlay |
| `Essentials` | NanaZip and current PowerShell |
| `Java` | Corretto 25, 21, 17, and 8 JDKs |
| `Legacy` | .NET Framework 3.5 Windows feature |
| `Workbench` | Optional desktop tools listed above |

Use `-Profile Custom -IncludeGroup` to install only the selected groups. For
example, `-IncludeGroup Java` installs all four Corretto versions; select
individual package IDs with `-IncludePackage` when you only need one version.

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

# Install every supported Corretto JDK line
.\Install.ps1 -Profile Custom -IncludeGroup Java -Unattended

# Install only Corretto 21
.\Install.ps1 -Profile Custom -IncludePackage Amazon.Corretto.21.JDK -Unattended

# Enable .NET Framework 3.5 for legacy applications
.\Install.ps1 -Profile Custom -IncludeGroup Legacy -Unattended

# Show the complete manifest
.\Install.ps1 -ListPackages
```

`Modern` and `Full` remain accepted as aliases for `Recommended`. `Legacy` is a
custom component group for .NET Framework 3.5; use `-Profile Full` for the old
profile alias.

Exit code `0` means success, `1` means a fatal setup error, and `2` means one or
more items failed or the elevated run was interrupted.

## Releases

Each release includes a version-pinned BAT, ZIP, `tar.gz`, gzip-compressed
PowerShell source, and `SHA256SUMS.txt`. GitHub also generates its standard
source ZIP and source tarball.

WinGet verifies installer hashes against its manifests. By default, AEGIS checks
the latest stable and prerelease versions and picks the higher one, preferring
prerelease when the versions tie. If prerelease lookup or installation fails,
AEGIS falls back to stable. Use `-WinGetChannel Stable` to stay on stable, or
`Preview` to require a prerelease. AEGIS checks the published SHA-256 hashes of
the WinGet release bundle and dependency archive before installing them. It
uses exact package IDs and explicit WinGet or Microsoft Store sources, retries
packages independently, and writes its log under `%TEMP%` unless `-LogPath` is
supplied.

## Credit

Conceptually inspired by
[PC-Gaming-Redists](https://github.com/harryeffinpotter/PC-Gaming-Redists) by
[`@harryeffinpotter`](https://github.com/harryeffinpotter).

AEGIS is an independent clean-room implementation and shares no source code
with PC-Gaming-Redists. Released under the [MIT License](LICENSE).
