#requires -Version 5.1
<#
.SYNOPSIS
    AEGIS - Automated Essentials for Gaming Installation System.

.DESCRIPTION
    Installs the complete curated Windows gaming prerequisite stack through
    WinGet. AEGIS is designed to run as a local script or through:

        irm <raw Install.ps1 URL> | iex

    Dry-run mode never installs packages, changes Windows features, or updates
    WinGet.
#>

[CmdletBinding()]
param(
    [Alias('Profile')]
    [ValidateSet('Interactive', 'Recommended', 'Custom', 'Modern', 'Legacy', 'Full')]
    [string]$AegisProfile = 'Interactive',

    [string[]]$IncludeGroup = @(),

    [string[]]$IncludePackage = @(),
    [string[]]$ExcludePackage = @(),

    [ValidateSet('Stable', 'Preview', 'Newest')]
    [string]$WinGetChannel = 'Newest',

    [switch]$Unattended,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoColor,
    [switch]$SkipWinGetUpdate,
    [switch]$ListPackages,
    [switch]$Help,
    [switch]$Elevated,

    [ValidateRange(1, 10)]
    [int]$RetryCount = 3,

    [string]$LogPath = (Join-Path $env:TEMP (
        'AEGIS-{0}-{1:yyyyMMdd-HHmmss-fff}-{2}.log' -f
            $env:COMPUTERNAME, (Get-Date), $PID
    ))
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:AegisBoundParameters = @{} + $PSBoundParameters

$script:AegisVersion = '0.3.0'
$script:AegisSourceUrl = 'https://github.com/Marek-Codex/AEGIS/raw/refs/heads/main/Install.ps1'
$script:RunningFromFile = -not [string]::IsNullOrWhiteSpace($PSCommandPath)
$script:RebootRequired = $false
$script:Results = New-Object System.Collections.Generic.List[object]
$script:LogPath = $LogPath
$supportsVirtualTerminal = $false
try {
    $supportsVirtualTerminal = [bool]$Host.UI.SupportsVirtualTerminal
}
catch {
    # Legacy hosts use the plain fallback instead of printing escape codes.
}
$script:UseColor = -not $NoColor -and -not [Console]::IsOutputRedirected -and
    $supportsVirtualTerminal
$script:UseUnicode = $script:UseColor
$script:AegisIsWindows = $env:OS -eq 'Windows_NT'

if ($script:AegisIsWindows) {
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    }
    catch {
        # Output encoding is cosmetic; installation can continue.
    }
}

if (-not [Console]::IsOutputRedirected) {
    try {
        [Console]::BackgroundColor = [ConsoleColor]::Black
        [Console]::ForegroundColor = [ConsoleColor]::Gray
        [Console]::Clear()
    }
    catch {
        # Console appearance is cosmetic; unsupported hosts keep their defaults.
    }
}

$escape = [char]27
$script:Theme = @{
    Accent    = "$escape[38;2;60;160;255m"
    Secondary = "$escape[38;2;160;60;255m"
    Text      = "$escape[38;2;231;237;245m"
    Muted     = "$escape[38;2;142;154;170m"
    Success   = "$escape[38;2;78;214;167m"
    Warning   = "$escape[38;2;240;179;90m"
    Failure   = "$escape[38;2;240;93;104m"
    Reset     = "$escape[0m"
}

function Write-AegisLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $parent = Split-Path -Parent $script:LogPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $entry = '[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}' -f (Get-Date), $Level, $Message
    Add-Content -LiteralPath $script:LogPath -Value $entry -Encoding UTF8
}

function Write-Aegis {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('Normal', 'Muted', 'Accent', 'Secondary', 'Success', 'Warning', 'Failure')]
        [string]$Style = 'Normal',

        [switch]$NoNewline,
        [switch]$SkipLog
    )

    $colorKey = switch ($Style) {
        'Normal' { 'Text' }
        default { $Style }
    }

    $rendered = $Message
    if ($script:UseColor) {
        $rendered = '{0}{1}{2}' -f $script:Theme[$colorKey], $Message, $script:Theme.Reset
    }

    if ($NoNewline) {
        Write-Host $rendered -NoNewline
    }
    else {
        Write-Host $rendered
    }

    if (-not $SkipLog) {
        $level = switch ($Style) {
            'Warning' { 'WARN' }
            'Failure' { 'ERROR' }
            'Success' { 'SUCCESS' }
            default { 'INFO' }
        }
        Write-AegisLog -Message $Message -Level $level
    }
}

function Show-AegisHeader {
    param([switch]$Compact)

    $rule = Get-AegisGlyph Rule
    if ($Compact) {
        Write-Host ''
        Write-Aegis ('  AEGIS {0}  /  AUTOMATED ESSENTIALS FOR GAMING INSTALLATION SYSTEM' -f
            $script:AegisVersion) -Style Secondary -SkipLog
        Write-Aegis ('  ' + ($rule * 62)) -Style Accent -SkipLog
        Write-Host ''
        return
    }

    $logo = @'
.s5SSSs.  .s5SSSs.  .s5SSSs.  s.  .s5SSSs.
      SS.       SS.       SS. SS.       SS.
sS    S%S sS    `:; sS    `:; S%S sS    `:;
SS    S%S SS        SS        S%S SS
SSSs. S%S SSSs.     SS        S%S `:;;;;.
SS    S%S SS        SS        S%S       ;;.
SS    `:; SS        SS   ``:; `:;       `:;
SS    ;,. SS    ;,. SS    ;,. ;,. .,;   ;,.
:;    ;:' `:;;;;;:' `:;;;;;:' ;:' `:;;;;;:'
'@

    $shellVersion = $PSVersionTable.PSVersion.ToString()

    Write-Host ''
    foreach ($line in ($logo -split "`r?`n")) {
        if ($script:UseColor) {
            $rendered = $line -replace '([\.,;:`])', ($script:Theme.Muted + '$1' + $script:Theme.Accent)
            Write-Host ($script:Theme.Accent + $rendered + $script:Theme.Reset)
        }
        else {
            Write-Host $line
        }
    }
    $architecture = if ([Environment]::Is64BitOperatingSystem) { '64-BIT WINDOWS' } else { '32-BIT WINDOWS' }
    Write-Host ''
    Write-Aegis '  AUTOMATED ESSENTIALS FOR GAMING INSTALLATION SYSTEM' -Style Muted -SkipLog
    Write-Aegis ('  AEGIS {0}  /  POWERSHELL {1}  /  {2}' -f `
        $script:AegisVersion, $shellVersion, $architecture) -Style Secondary -SkipLog
    Write-Aegis ('  ' + ($rule * 62)) -Style Accent -SkipLog
    Write-Host ''
}

function Show-AegisHelp {
    @'
AEGIS - Automated Essentials for Gaming Installation System

USAGE
  .\Install.ps1                                   Interactive menu
  .\Install.ps1 -Profile Recommended -Unattended  Recommended stack, no prompts
  .\Install.ps1 -Profile Recommended -DryRun      Preview without changing Windows
  .\Install.ps1 -Profile Custom -IncludeGroup VC++,DotNet,AspNet
  .\Install.ps1 -Profile Custom -IncludePackage Amazon.Corretto.21.JDK
  .\Install.ps1 -ListPackages                     Show every package ID

MENU
  1  Install recommended   The curated runtime stack plus Corretto 25.
  2  Customize runtimes    Toggle families or expand them to pick versions.
  3  Workbench apps        Optional desktop tools, kept apart from runtimes.

COMPONENTS (-IncludeGroup)
  VC++, DotNet, AspNet, Gaming, Essentials, Java, Legacy, Workbench

OPTIONS
  -ExcludePackage <id>     Remove specific package IDs from a selection.
  -Force                   Reinstall packages that are already present.
  -RetryCount <1-10>       Attempts per package (default 3).
  -WinGetChannel <name>    Newest (default), Stable, or Preview.
  -SkipWinGetUpdate        Use the installed WinGet without checking for updates.
  -LogPath <path>          Write the log somewhere other than %TEMP%.
  -NoColor                 Plain output for logs and old consoles.

COMPATIBILITY
  Modern and Full remain accepted as aliases for -Profile Recommended.

EXIT CODES
  0  Completed successfully.
  1  Fatal bootstrap or configuration error.
  2  Items failed, or elevated setup was interrupted.
'@ | Write-Host
}

function New-AegisPackage {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Category,
        [string[]]$Profiles = @(),
        [string[]]$Groups = @(),
        [ValidateSet('WinGet', 'WindowsFeature')]
        [string]$Kind = 'WinGet',
        [string]$FeatureName = '',
        [ValidateSet('Any', 'x64', 'arm64')]
        [string]$Architecture = 'Any',
        [ValidateSet('winget', 'msstore')]
        [string]$Source = 'winget'
    )

    [pscustomobject]@{
        Id           = $Id
        Name         = $Name
        Category     = $Category
        Profiles     = $Profiles
        Groups       = $Groups
        Kind         = $Kind
        FeatureName  = $FeatureName
        Architecture = $Architecture
        Source       = $Source
    }
}

function Get-AegisManifest {
    @(
        # x86 is required for 32-bit games even on 64-bit Windows.
        New-AegisPackage 'Microsoft.VCRedist.2005.x86' 'Microsoft Visual C++ 2005 Redistributable (x86)' 'VC++' @('Recommended') @('VC++')
        New-AegisPackage 'Microsoft.VCRedist.2005.x64' 'Microsoft Visual C++ 2005 Redistributable (x64)' 'VC++' @('Recommended') @('VC++') 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2008.x86' 'Microsoft Visual C++ 2008 Redistributable (x86)' 'VC++' @('Recommended') @('VC++')
        New-AegisPackage 'Microsoft.VCRedist.2008.x64' 'Microsoft Visual C++ 2008 Redistributable (x64)' 'VC++' @('Recommended') @('VC++') 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2010.x86' 'Microsoft Visual C++ 2010 Redistributable (x86)' 'VC++' @('Recommended') @('VC++')
        New-AegisPackage 'Microsoft.VCRedist.2010.x64' 'Microsoft Visual C++ 2010 Redistributable (x64)' 'VC++' @('Recommended') @('VC++') 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2012.x86' 'Microsoft Visual C++ 2012 Redistributable (x86)' 'VC++' @('Recommended') @('VC++')
        New-AegisPackage 'Microsoft.VCRedist.2012.x64' 'Microsoft Visual C++ 2012 Redistributable (x64)' 'VC++' @('Recommended') @('VC++') 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2013.x86' 'Microsoft Visual C++ 2013 Redistributable (x86)' 'VC++' @('Recommended') @('VC++')
        New-AegisPackage 'Microsoft.VCRedist.2013.x64' 'Microsoft Visual C++ 2013 Redistributable (x64)' 'VC++' @('Recommended') @('VC++') 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2015+.x86' 'Microsoft Visual C++ v14 Redistributable (x86)' 'VC++' @('Recommended') @('VC++')
        New-AegisPackage 'Microsoft.VCRedist.2015+.x64' 'Microsoft Visual C++ v14 Redistributable (x64)' 'VC++' @('Recommended') @('VC++') 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2015+.arm64' 'Microsoft Visual C++ v14 Redistributable (Arm64)' 'VC++' @('Recommended') @('VC++') 'WinGet' '' 'arm64'

        # All non-preview Windows Desktop runtime families currently in WinGet.
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.3_1' 'Microsoft .NET Desktop Runtime 3.1' '.NET Desktop' @('Recommended') @('DotNet')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.5' 'Microsoft .NET Desktop Runtime 5' '.NET Desktop' @('Recommended') @('DotNet')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.6' 'Microsoft .NET Desktop Runtime 6 (x64)' '.NET Desktop' @('Recommended') @('DotNet') 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.6.x86' 'Microsoft .NET Desktop Runtime 6 (x86)' '.NET Desktop' @('Recommended') @('DotNet')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.7' 'Microsoft .NET Desktop Runtime 7 (x64)' '.NET Desktop' @('Recommended') @('DotNet') 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.7.x86' 'Microsoft .NET Desktop Runtime 7 (x86)' '.NET Desktop' @('Recommended') @('DotNet')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.8' 'Microsoft .NET Desktop Runtime 8 (x64)' '.NET Desktop' @('Recommended') @('DotNet') 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.8.x86' 'Microsoft .NET Desktop Runtime 8 (x86)' '.NET Desktop' @('Recommended') @('DotNet')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.8.arm64' 'Microsoft .NET Desktop Runtime 8 (Arm64)' '.NET Desktop' @('Recommended') @('DotNet') 'WinGet' '' 'arm64'
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.9' 'Microsoft .NET Desktop Runtime 9' '.NET Desktop' @('Recommended') @('DotNet')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.10' 'Microsoft .NET Desktop Runtime 10' '.NET Desktop' @('Recommended') @('DotNet')

        # Runtime packages only; omit legacy entries WinGet identifies as SDKs.
        New-AegisPackage 'Microsoft.DotNet.AspNetCore.2_1' 'Microsoft ASP.NET Core Runtime 2.1' 'ASP.NET Core' @('Recommended') @('AspNet')
        New-AegisPackage 'Microsoft.DotNet.AspNetCore.3_1' 'Microsoft ASP.NET Core Runtime 3.1' 'ASP.NET Core' @('Recommended') @('AspNet')
        New-AegisPackage 'Microsoft.DotNet.AspNetCore.5' 'Microsoft ASP.NET Core Runtime 5' 'ASP.NET Core' @('Recommended') @('AspNet')
        New-AegisPackage 'Microsoft.DotNet.AspNetCore.6' 'Microsoft ASP.NET Core Runtime 6' 'ASP.NET Core' @('Recommended') @('AspNet')
        New-AegisPackage 'Microsoft.DotNet.AspNetCore.7' 'Microsoft ASP.NET Core Runtime 7' 'ASP.NET Core' @('Recommended') @('AspNet')
        New-AegisPackage 'Microsoft.DotNet.AspNetCore.8' 'Microsoft ASP.NET Core Runtime 8' 'ASP.NET Core' @('Recommended') @('AspNet')
        New-AegisPackage 'Microsoft.DotNet.AspNetCore.9' 'Microsoft ASP.NET Core Runtime 9' 'ASP.NET Core' @('Recommended') @('AspNet')
        New-AegisPackage 'Microsoft.DotNet.AspNetCore.10' 'Microsoft ASP.NET Core Runtime 10' 'ASP.NET Core' @('Recommended') @('AspNet')

        # Gaming compatibility additions retained from AEGIS.
        New-AegisPackage 'Microsoft.DirectX' 'DirectX End-User Runtime' 'Gaming Compatibility' @('Recommended') @('Gaming')
        New-AegisPackage 'Microsoft.XNARedist' 'Microsoft XNA Framework Redistributable' 'Gaming Compatibility' @('Recommended') @('Gaming')
        New-AegisPackage 'CreativeTechnology.OpenAL' 'OpenAL' 'Gaming Compatibility' @('Recommended') @('Gaming')
        New-AegisPackage 'Microsoft.EdgeWebView2Runtime' 'Microsoft Edge WebView2 Runtime' 'Gaming Compatibility' @('Recommended') @('Gaming')
        New-AegisPackage 'Nvidia.PhysX' 'NVIDIA PhysX System Software' 'Gaming Compatibility' @('Recommended') @('Gaming') 'WinGet' '' 'x64'
        New-AegisPackage 'Nvidia.PhysXLegacy' 'NVIDIA PhysX Legacy' 'Gaming Compatibility' @('Recommended') @('Gaming') 'WinGet' '' 'x64'
        New-AegisPackage 'Windows.DirectPlay' 'DirectPlay' 'Gaming Compatibility' @('Recommended') @('Gaming') 'WindowsFeature' 'DirectPlay'

        # NanaZip replaces 7-Zip; current PowerShell supplements inbox 5.1.
        New-AegisPackage 'M2Team.NanaZip' 'NanaZip' 'Essentials' @('Recommended') @('Essentials')
        New-AegisPackage 'Microsoft.PowerShell' 'PowerShell' 'Essentials' @('Recommended') @('Essentials')

        # Java is part of the default gaming/development compatibility stack.
        New-AegisPackage 'Amazon.Corretto.25.JDK' 'Amazon Corretto 25 JDK' 'Java' @('Recommended') @('Java')
        New-AegisPackage 'Amazon.Corretto.21.JDK' 'Amazon Corretto 21 JDK' 'Java' @() @('Java')
        New-AegisPackage 'Amazon.Corretto.17.JDK' 'Amazon Corretto 17 JDK' 'Java' @() @('Java')
        New-AegisPackage 'Amazon.Corretto.8.JDK' 'Amazon Corretto 8 JDK (legacy)' 'Java' @() @('Java')

        # .NET Framework 3.5 covers legacy desktop software and older games.
        New-AegisPackage 'Windows.NetFx3' '.NET Framework 3.5 (includes 2.0 and 3.0)' `
            'Legacy Windows' @() @('Legacy') 'WindowsFeature' 'NetFx3'

        # Optional desktop tools, including explicitly labeled prerelease channels.
        New-AegisPackage -Id 'Devolutions.UniGetUI' -Name 'UniGetUI' `
            -Category 'Power User Workbench' -Groups @('Workbench')
        New-AegisPackage -Id 'voidtools.Everything.Beta' -Name 'Everything Beta [PRE-RELEASE]' `
            -Category 'Power User Workbench' -Groups @('Workbench')
        New-AegisPackage -Id 'VideoLAN.VLC.Nightly' -Name 'VLC Nightly [PRE-RELEASE]' `
            -Category 'Power User Workbench' -Groups @('Workbench')
        New-AegisPackage -Id '9N5JJZW4QZBR' -Name 'Xtreme Download Manager (Microsoft Store)' `
            -Category 'Power User Workbench' -Groups @('Workbench') -Source 'msstore'
        New-AegisPackage -Id 'SublimeHQ.SublimeText.4' -Name 'Sublime Text 4' `
            -Category 'Power User Workbench' -Groups @('Workbench')
        New-AegisPackage -Id 'Microsoft.VisualStudioCode.Insiders' `
            -Name 'Visual Studio Code Insiders [PRE-RELEASE]' `
            -Category 'Power User Workbench' -Groups @('Workbench')
        New-AegisPackage -Id 'AntibodySoftware.WizTree' -Name 'WizTree' `
            -Category 'Power User Workbench' -Groups @('Workbench')
    )
}

$script:AegisGroups = @(
    [pscustomobject]@{ Key = 'VC++'; Label = 'Visual C++ Redistributables'; Hint = '2005 through v14, x86 plus native 64-bit' }
    [pscustomobject]@{ Key = 'DotNet'; Label = '.NET Desktop Runtimes'; Hint = '3.1 through 10' }
    [pscustomobject]@{ Key = 'AspNet'; Label = 'ASP.NET Core Runtimes'; Hint = '2.1 through 10' }
    [pscustomobject]@{ Key = 'Gaming'; Label = 'Gaming Compatibility'; Hint = 'DirectX, XNA, OpenAL, WebView2, PhysX, DirectPlay' }
    [pscustomobject]@{ Key = 'Essentials'; Label = 'Essentials'; Hint = 'NanaZip and current PowerShell' }
    [pscustomobject]@{ Key = 'Java'; Label = 'Java (Amazon Corretto)'; Hint = '25 by default; 21, 17 and 8 for launchers or modpacks that need them' }
    [pscustomobject]@{ Key = 'Legacy'; Label = '.NET Framework 3.5'; Hint = 'Legacy Windows feature; also provides 2.0 and 3.0' }
    [pscustomobject]@{ Key = 'Workbench'; Label = 'Power User Workbench'; Hint = 'Optional desktop tools; some are pre-release builds' }
)

function Get-NativeArchitecture {
    if ($env:PROCESSOR_ARCHITEW6432) {
        return $env:PROCESSOR_ARCHITEW6432
    }
    return $env:PROCESSOR_ARCHITECTURE
}

function Test-PackageArchitecture {
    param([object]$Package)

    $architecture = Get-NativeArchitecture
    switch ($Package.Architecture) {
        # Windows 11 on Arm can run x64 and x86 applications, so those runtime
        # families remain relevant there as well.
        'x64' { return $architecture -in @('AMD64', 'ARM64') }
        'arm64' { return $architecture -eq 'ARM64' }
        default { return $true }
    }
}

function Get-SelectedPackages {
    param(
        [object[]]$Manifest,
        [string]$SelectedProfile,
        [string[]]$Groups,
        [string[]]$ExplicitPackages,
        [string[]]$ExcludedPackages
    )

    $selected = New-Object System.Collections.Generic.List[object]

    foreach ($package in $Manifest) {
        $profileMatch = $SelectedProfile -ne 'Custom' -and $package.Profiles -contains $SelectedProfile
        $groupMatch = @($package.Groups | Where-Object { $Groups -contains $_ }).Count -gt 0
        $explicitMatch = $ExplicitPackages -contains $package.Id

        if (($profileMatch -or $groupMatch -or $explicitMatch) -and
            $ExcludedPackages -notcontains $package.Id -and
            (Test-PackageArchitecture -Package $package)) {
            $selected.Add($package)
        }
    }

    foreach ($id in $ExplicitPackages) {
        if (-not ($Manifest.Id -contains $id)) {
            throw "Unknown package ID supplied to -IncludePackage: $id"
        }
    }

    $categoryOrder = @{
        'VC++'                  = 0
        '.NET Desktop'          = 1
        'ASP.NET Core'          = 2
        'Gaming Compatibility'  = 3
        Essentials              = 4
        Java                    = 5
        'Legacy Windows' = 6
        'Power User Workbench'  = 7
    }

    $architectureOrder = @{
        Any   = 0
        x64   = 1
        arm64 = 2
    }

    # Pad numbers so versions sort naturally: 3.1, 5, ... 10 rather than 10, 3.1, 5.
    return @($selected | Sort-Object `
        @{ Expression = { $categoryOrder[$_.Category] } }, `
        @{ Expression = {
            [regex]::Replace(($_.Name -replace ' \((x86|x64|Arm64)\)$', ''), '\d+',
                { param($match) $match.Value.PadLeft(5, '0') })
        } }, `
        @{ Expression = { $architectureOrder[$_.Architecture] } }, Name -Unique)
}

function Get-AegisGlyph {
    param([string]$Name)

    if ($script:UseUnicode) {
        switch ($Name) {
            'Cursor' { return [string][char]0x25B8 }
            'Ok' { return [string][char]0x2713 }
            'Fail' { return [string][char]0x2717 }
            'Pending' { return [string][char]0x2022 }
            'Dot' { return [string][char]0x00B7 }
            'Rule' { return [string][char]0x2501 }
        }
    }

    switch ($Name) {
        'Cursor' { return '>' }
        'Ok' { return '+' }
        'Fail' { return 'x' }
        'Pending' { return '.' }
        'Dot' { return '/' }
        'Rule' { return '=' }
    }
}

function Test-AegisKeyInput {
    try {
        return -not [Console]::IsInputRedirected -and
            -not [Console]::IsOutputRedirected -and
            [Console]::WindowWidth -ge 40
    }
    catch {
        return $false
    }
}

function Get-AegisWidth {
    try {
        if (-not [Console]::IsOutputRedirected) {
            return [Math]::Max(60, [Math]::Min(110, [Console]::WindowWidth - 1))
        }
    }
    catch {
        # Fall through to a fixed width for hosts without a console window.
    }
    return 100
}

function Reset-AegisScreen {
    param([switch]$Compact)

    if (-not [Console]::IsOutputRedirected) {
        try {
            [Console]::Clear()
        }
        catch {
            # Hosts without a clearable buffer simply keep scrolling.
        }
    }
    Show-AegisHeader -Compact:$Compact
}

function Get-KeyDigit {
    param([ConsoleKeyInfo]$Key)

    if ([char]::IsDigit($Key.KeyChar)) {
        return [int]::Parse([string]$Key.KeyChar)
    }
    return -1
}

function Get-AegisShortName {
    param([object]$Package)

    # Category headings already say what these are; keep only the part that differs.
    $name = $Package.Name
    foreach ($prefix in @(
        '^Microsoft Visual C\+\+ ',
        '^Microsoft \.NET Desktop Runtime ',
        '^Microsoft ASP\.NET Core Runtime ',
        '^Amazon Corretto '
    )) {
        $name = $name -replace $prefix, ''
    }
    return $name -replace ' Redistributable', ''
}

function Read-MenuChoice {
    param(
        [string]$Prompt,
        [object[]]$Choices,
        [int]$Default = 0
    )

    if (Test-AegisKeyInput) {
        $position = $Default
        try {
            [Console]::CursorVisible = $false
            while ($true) {
                Reset-AegisScreen
                Write-Aegis ('  {0}' -f $Prompt) -Style Accent -SkipLog
                if ($DryRun) {
                    Write-Aegis '  PREVIEW MODE  /  NOTHING WILL BE INSTALLED' -Style Warning -SkipLog
                }
                Write-Host ''

                for ($index = 0; $index -lt $Choices.Count; $index++) {
                    $active = $index -eq $position
                    $prefix = if ($active) { '  ' + (Get-AegisGlyph Cursor) } else { '   ' }
                    $style = if ($active) { 'Secondary' } else { 'Normal' }
                    Write-Aegis ('{0} {1}  {2}' -f $prefix, ($index + 1), $Choices[$index].Label.ToUpperInvariant()) `
                        -Style $style -SkipLog
                    Write-Aegis ('       {0}' -f $Choices[$index].Hint) -Style Muted -SkipLog
                    Write-Host ''
                }

                Write-Aegis ('  UP/DOWN  MOVE     ENTER  SELECT     1-{0}  QUICK PICK     ESC  EXIT' -f
                    $Choices.Count) -Style Muted -SkipLog

                $key = [Console]::ReadKey($true)
                $digit = Get-KeyDigit -Key $key
                if ($digit -ge 1 -and $digit -le $Choices.Count) {
                    return $digit - 1
                }

                switch ($key.Key) {
                    { $_ -in 'UpArrow', 'W', 'K' } { $position = ($position - 1 + $Choices.Count) % $Choices.Count }
                    { $_ -in 'DownArrow', 'S', 'J' } { $position = ($position + 1) % $Choices.Count }
                    'Enter' { return $position }
                    { $_ -in 'Escape', 'Q', 'D0', 'NumPad0' } { return -1 }
                }
            }
        }
        finally {
            [Console]::CursorVisible = $true
        }
    }

    Write-Aegis $Prompt -Style Accent -SkipLog
    for ($index = 0; $index -lt $Choices.Count; $index++) {
        Write-Aegis ('  [{0}] {1}  -  {2}' -f ($index + 1), $Choices[$index].Label, $Choices[$index].Hint) -SkipLog
    }
    Write-Aegis '  [0] Exit' -SkipLog
    while ($true) {
        $answer = Read-Host ('Select [{0}]' -f ($Default + 1))
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }

        $number = 0
        if ([int]::TryParse($answer.Trim(), [ref]$number) -and
            $number -ge 0 -and $number -le $Choices.Count) {
            return $number - 1
        }
        Write-Aegis 'Invalid selection.' -Style Warning -SkipLog
    }
}

function Read-PackagePicker {
    param(
        [string]$Title,
        [object[]]$Manifest,
        [string[]]$Groups,
        [string[]]$DefaultIds = @(),
        [switch]$ExpandAll
    )

    $groupDefs = @($script:AegisGroups | Where-Object { $Groups -contains $_.Key })
    $packagesByGroup = @{}
    $allPackages = New-Object System.Collections.Generic.List[object]
    foreach ($group in $groupDefs) {
        $members = @(Get-SelectedPackages -Manifest $Manifest -SelectedProfile 'Custom' `
            -Groups @($group.Key) -ExplicitPackages @() -ExcludedPackages @())
        $packagesByGroup[$group.Key] = $members
        foreach ($member in $members) {
            $allPackages.Add($member)
        }
    }

    $checked = @{}
    $expanded = @{}
    foreach ($package in $allPackages) {
        $checked[$package.Id] = $DefaultIds -contains $package.Id
    }
    foreach ($group in $groupDefs) {
        $expanded[$group.Key] = [bool]$ExpandAll
    }

    if (-not (Test-AegisKeyInput)) {
        Write-Aegis $Title -Style Accent -SkipLog
        for ($index = 0; $index -lt $groupDefs.Count; $index++) {
            Write-Aegis ('  [{0}] {1}  -  {2}' -f ($index + 1), $groupDefs[$index].Label, $groupDefs[$index].Hint) -SkipLog
        }
        Write-Aegis 'Enter comma-separated numbers, 0 to go back, or press Enter for the defaults.' -Style Muted -SkipLog
        $answer = Read-Host 'Select'
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return ,@($allPackages | Where-Object { $checked[$_.Id] } | ForEach-Object { $_.Id })
        }
        if ($answer.Trim() -eq '0') {
            return $null
        }

        $ids = New-Object System.Collections.Generic.List[string]
        foreach ($token in ($answer -split ',')) {
            $number = 0
            if (-not [int]::TryParse($token.Trim(), [ref]$number) -or
                $number -lt 1 -or $number -gt $groupDefs.Count) {
                throw "Invalid component selection: $token"
            }
            foreach ($package in $packagesByGroup[$groupDefs[$number - 1].Key]) {
                if (-not $ids.Contains($package.Id)) {
                    $ids.Add($package.Id)
                }
            }
        }
        return ,$ids.ToArray()
    }

    $position = 0
    $notice = ''
    try {
        [Console]::CursorVisible = $false
        while ($true) {
            $rows = New-Object System.Collections.Generic.List[object]
            foreach ($group in $groupDefs) {
                $rows.Add([pscustomobject]@{ Group = $group; Package = $null })
                if ($expanded[$group.Key]) {
                    foreach ($package in $packagesByGroup[$group.Key]) {
                        $rows.Add([pscustomobject]@{ Group = $group; Package = $package })
                    }
                }
            }
            $position = [Math]::Min($position, $rows.Count - 1)

            # The full logo needs about 15 lines; drop to the one-line header
            # rather than scrolling the list off a small window.
            $compact = $false
            try {
                $compact = [Console]::WindowHeight -lt ($rows.Count + 24)
            }
            catch {
                $compact = $false
            }
            Reset-AegisScreen -Compact:$compact

            $selectedCount = @($allPackages | Where-Object { $checked[$_.Id] }).Count
            Write-Aegis ('  {0}' -f $Title) -Style Accent -SkipLog
            Write-Aegis ('  {0} OF {1} ITEMS SELECTED' -f $selectedCount, $allPackages.Count) -Style Muted -SkipLog
            Write-Host ''

            for ($index = 0; $index -lt $rows.Count; $index++) {
                $row = $rows[$index]
                $active = $index -eq $position
                $cursor = if ($active) { Get-AegisGlyph Cursor } else { ' ' }

                if ($null -eq $row.Package) {
                    $members = $packagesByGroup[$row.Group.Key]
                    $on = @($members | Where-Object { $checked[$_.Id] }).Count
                    $box = if ($on -eq $members.Count) { '[x]' } elseif ($on -gt 0) { '[~]' } else { '[ ]' }
                    $fold = if ($expanded[$row.Group.Key]) { '-' } else { '+' }
                    $style = if ($active) { 'Secondary' } elseif ($on -gt 0) { 'Normal' } else { 'Muted' }
                    Write-Aegis ('  {0} {1} {2} {3,-32} {4,5}' -f $cursor, $box, $fold, $row.Group.Label,
                        ('{0}/{1}' -f $on, $members.Count)) -Style $style -SkipLog
                    if ($active -and -not $expanded[$row.Group.Key]) {
                        Write-Aegis ('          {0}' -f $row.Group.Hint) -Style Muted -SkipLog
                    }
                }
                else {
                    $box = if ($checked[$row.Package.Id]) { '[x]' } else { '[ ]' }
                    $style = if ($active) { 'Secondary' } elseif ($checked[$row.Package.Id]) { 'Normal' } else { 'Muted' }
                    Write-Aegis ('  {0}       {1} {2}' -f $cursor, $box, $row.Package.Name) -Style $style -SkipLog
                }
            }

            Write-Host ''
            if ($notice) {
                Write-Aegis ('  {0}' -f $notice) -Style Warning -SkipLog
                $notice = ''
            }
            Write-Aegis '  UP/DOWN  MOVE     SPACE  TOGGLE     RIGHT/LEFT  SHOW/HIDE VERSIONS' -Style Muted -SkipLog
            Write-Aegis '  A  ALL     N  NONE     ENTER  REVIEW PLAN     ESC  BACK' -Style Muted -SkipLog

            $key = [Console]::ReadKey($true)
            $row = $rows[$position]
            switch ($key.Key) {
                { $_ -in 'UpArrow', 'W', 'K' } { $position = ($position - 1 + $rows.Count) % $rows.Count }
                { $_ -in 'DownArrow', 'S', 'J' } { $position = ($position + 1) % $rows.Count }
                { $_ -in 'RightArrow', 'L' } { $expanded[$row.Group.Key] = $true }
                { $_ -in 'LeftArrow', 'H' } {
                    $expanded[$row.Group.Key] = $false
                    for ($index = 0; $index -lt $rows.Count; $index++) {
                        if ($null -eq $rows[$index].Package -and $rows[$index].Group.Key -eq $row.Group.Key) {
                            $position = $index
                            break
                        }
                    }
                }
                'Spacebar' {
                    if ($null -eq $row.Package) {
                        $members = $packagesByGroup[$row.Group.Key]
                        $allOn = @($members | Where-Object { $checked[$_.Id] }).Count -eq $members.Count
                        foreach ($member in $members) {
                            $checked[$member.Id] = -not $allOn
                        }
                    }
                    else {
                        $checked[$row.Package.Id] = -not $checked[$row.Package.Id]
                    }
                }
                'A' {
                    foreach ($package in $allPackages) {
                        $checked[$package.Id] = $true
                    }
                }
                'N' {
                    foreach ($package in $allPackages) {
                        $checked[$package.Id] = $false
                    }
                }
                'Enter' {
                    $ids = @($allPackages | Where-Object { $checked[$_.Id] } | ForEach-Object { $_.Id })
                    if ($ids.Count -gt 0) {
                        return ,$ids
                    }
                    $notice = 'Select at least one item.'
                }
                { $_ -in 'Escape', 'Backspace', 'D0', 'NumPad0' } { return $null }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }
}

function Read-AegisSelection {
    param([object[]]$Manifest)

    $recommendedIds = @(Get-SelectedPackages -Manifest $Manifest -SelectedProfile 'Recommended' `
        -Groups @() -ExplicitPackages @() -ExcludedPackages @() | ForEach-Object { $_.Id })
    $runtimeGroups = @($script:AegisGroups | Where-Object { $_.Key -ne 'Workbench' } | ForEach-Object { $_.Key })

    while ($true) {
        $ids = $null
        $choice = Read-MenuChoice -Prompt 'WHAT WOULD YOU LIKE TO DO?' -Choices @(
            [pscustomobject]@{
                Label = 'Install recommended'
                Hint  = '{0} items: VC++, .NET, DirectX, XNA, PhysX, OpenAL, Java 25 and more' -f $recommendedIds.Count
            }
            [pscustomobject]@{
                Label = 'Customize runtimes'
                Hint  = 'Pick families or individual versions; add Java 8-21 or .NET 3.5'
            }
            [pscustomobject]@{
                Label = 'Workbench apps'
                Hint  = 'Optional desktop tools, kept separate from the runtime stack'
            }
        )

        switch ($choice) {
            0 { return ,$recommendedIds }
            1 {
                $ids = Read-PackagePicker -Title 'CUSTOMIZE RUNTIMES' -Manifest $Manifest `
                    -Groups $runtimeGroups -DefaultIds $recommendedIds
            }
            2 {
                $workbenchIds = @($Manifest | Where-Object { $_.Groups -contains 'Workbench' } | ForEach-Object { $_.Id })
                $ids = Read-PackagePicker -Title 'WORKBENCH APPS' -Manifest $Manifest `
                    -Groups @('Workbench') -DefaultIds $workbenchIds -ExpandAll
            }
            default { return $null }
        }

        if ($null -ne $ids) {
            return ,$ids
        }
    }
}

function Read-PlanConfirmation {
    $action = if ($DryRun) { 'RUN PREVIEW' } else { 'INSTALL' }
    if (Test-AegisKeyInput) {
        Write-Aegis ('  ENTER  {0}     ESC  BACK' -f $action) -Style Muted -SkipLog
        while ($true) {
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                { $_ -in 'Enter', 'Y' } { return $true }
                { $_ -in 'Escape', 'Backspace', 'N', 'D0', 'NumPad0' } { return $false }
            }
        }
    }

    $confirmation = Read-Host 'Continue? [Y/n]'
    return $confirmation -notmatch '^[Nn]'
}

function Test-WinGet {
    try {
        $output = & winget --version 2>&1 | Out-String
        return $LASTEXITCODE -eq 0 -and $output.Trim() -match '^v?\d+\.\d+'
    }
    catch {
        return $false
    }
}

function ConvertTo-VersionNumber {
    param([string]$Value)

    $match = [regex]::Match($Value, '\d+(?:\.\d+){1,3}')
    if (-not $match.Success) {
        return [version]'0.0'
    }
    return [version]$match.Value
}

function Get-WinGetRelease {
    param([string]$Channel)

    $headers = Get-WinGetGitHubHeaders

    if ($Channel -eq 'Stable') {
        return Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' `
            -Headers $headers -UseBasicParsing
    }

    $releases = Invoke-RestMethod `
        -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases?per_page=30' `
        -Headers $headers -UseBasicParsing

    $eligible = @($releases | Where-Object {
        -not $_.draft -and ($Channel -eq 'Newest' -or $_.prerelease)
    } | Sort-Object { [datetime]$_.published_at } -Descending)

    if ($eligible.Count -eq 0) {
        throw "No WinGet release matched channel '$Channel'."
    }
    return $eligible[0]
}

function Get-WinGetGitHubHeaders {
    $headers = @{
        'User-Agent' = 'AEGIS-Windows-Gaming-Installer'
        'Accept' = 'application/vnd.github+json'
    }

    if ($env:GITHUB_TOKEN) {
        $headers.Authorization = 'Bearer {0}' -f $env:GITHUB_TOKEN
    }

    return $headers
}

function Get-WinGetReleasePair {
    param([hashtable]$Headers)

    $releases = @(Invoke-RestMethod `
        -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases?per_page=30' `
        -Headers $Headers -UseBasicParsing)
    $stable = @($releases | Where-Object { -not $_.draft -and -not $_.prerelease } |
        Sort-Object { [datetime]$_.published_at } -Descending | Select-Object -First 1)
    $preview = @($releases | Where-Object { -not $_.draft -and $_.prerelease } |
        Sort-Object { [datetime]$_.published_at } -Descending | Select-Object -First 1)

    if (-not $stable -and -not $preview) {
        throw 'GitHub returned no published WinGet releases.'
    }
    return [pscustomobject]@{
        Stable = if ($stable) { $stable[0] } else { $null }
        Preview = if ($preview) { $preview[0] } else { $null }
    }
}

function Assert-ReleaseAssetHash {
    param(
        [object]$Release,
        [object]$Asset,
        [string]$Path
    )

    if ($Asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw "WinGet release asset '$($Asset.name)' has no published SHA-256 digest."
    }
    $expected = $Matches[1]
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ine $expected) {
        throw "SHA-256 verification failed for WinGet release asset '$($Asset.name)' in release '$($Release.tag_name)'."
    }
}

function Get-ReleaseAsset {
    param(
        [object]$Release,
        [string]$Name
    )

    $asset = @($Release.assets | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
    if (-not $asset) {
        throw "Release '$($Release.tag_name)' does not contain asset '$Name'."
    }
    return $asset
}

function Save-RemoteFile {
    param(
        [string]$Uri,
        [string]$Destination
    )

    $parameters = @{
        Uri = $Uri
        OutFile = $Destination
        UseBasicParsing = $true
        Headers = @{ 'User-Agent' = 'AEGIS-Windows-Gaming-Installer' }
    }
    Invoke-WebRequest @parameters

    if (-not (Test-Path -LiteralPath $Destination) -or
        (Get-Item -LiteralPath $Destination).Length -eq 0) {
        throw "Downloaded file is missing or empty: $Destination"
    }
}

function Assert-MicrosoftSignature {
    param([string]$Path)

    $signature = Get-AuthenticodeSignature -FilePath $Path
    if ($signature.Status -ne 'Valid' -or
        -not $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw "Signature verification failed for '$Path' (status: $($signature.Status))."
    }
}

function Install-WinGetRelease {
    param([object]$Release)

    $bundleName = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    $dependencyName = 'DesktopAppInstaller_Dependencies.zip'
    $bundleAsset = Get-ReleaseAsset -Release $Release -Name $bundleName
    $dependencyAsset = Get-ReleaseAsset -Release $Release -Name $dependencyName

    $tempRoot = Join-Path $env:TEMP ('AEGIS-WinGet-' + [guid]::NewGuid().ToString('N'))
    $bundlePath = Join-Path $tempRoot $bundleName
    $dependencyZip = Join-Path $tempRoot $dependencyName
    $dependencyRoot = Join-Path $tempRoot 'dependencies'

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        Write-Aegis ('Downloading WinGet {0}...' -f $Release.tag_name) -Style Accent
        Save-RemoteFile -Uri $bundleAsset.browser_download_url -Destination $bundlePath
        Save-RemoteFile -Uri $dependencyAsset.browser_download_url -Destination $dependencyZip
        Assert-ReleaseAssetHash -Release $Release -Asset $bundleAsset -Path $bundlePath
        Assert-ReleaseAssetHash -Release $Release -Asset $dependencyAsset -Path $dependencyZip
        Expand-Archive -LiteralPath $dependencyZip -DestinationPath $dependencyRoot -Force

        Assert-MicrosoftSignature -Path $bundlePath

        $native = Get-NativeArchitecture
        $architecturePattern = if ($native -eq 'ARM64') { 'arm64' } else { 'x64' }
        $dependencies = @(Get-ChildItem -LiteralPath $dependencyRoot -Recurse -File |
            Where-Object {
                $_.Extension -eq '.appx' -and
                ($_.Name -match $architecturePattern -or $_.Name -match 'neutral')
            })

        foreach ($dependency in $dependencies) {
            Assert-MicrosoftSignature -Path $dependency.FullName
        }

        $addParameters = @{
            Path = $bundlePath
            ForceApplicationShutdown = $true
            ErrorAction = 'Stop'
        }
        if ($dependencies.Count -gt 0) {
            $addParameters.DependencyPath = @($dependencies.FullName)
        }

        Add-AppxPackage @addParameters
        Write-Aegis ('WinGet {0} installed.' -f $Release.tag_name) -Style Success
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-WinGet {
    param(
        [string]$Channel,
        [switch]$SkipUpdate
    )

    $working = Test-WinGet
    if ($SkipUpdate -and $working) {
        Write-Aegis ('WinGet {0}' -f ((& winget --version) | Out-String).Trim()) -Style Success
        return
    }

    try {
        if ($Channel -eq 'Newest') {
            try {
                $pair = Get-WinGetReleasePair -Headers (Get-WinGetGitHubHeaders)
            }
            catch {
                Write-Aegis ('WinGet prerelease lookup failed; trying the latest stable release. {0}' -f
                    $_.Exception.Message) -Style Warning
                $pair = [pscustomobject]@{ Stable = (Get-WinGetRelease -Channel Stable); Preview = $null }
            }
            $release = if (-not $pair.Preview) { $pair.Stable }
                elseif (-not $pair.Stable) { $pair.Preview }
                elseif ((ConvertTo-VersionNumber -Value $pair.Preview.tag_name) -ge
                    (ConvertTo-VersionNumber -Value $pair.Stable.tag_name)) { $pair.Preview }
                else { $pair.Stable }
        }
        else {
            $release = Get-WinGetRelease -Channel $Channel
        }
        $releaseVersion = ConvertTo-VersionNumber -Value $release.tag_name

        if ($working) {
            $installedText = ((& winget --version) | Out-String).Trim()
            $installedVersion = ConvertTo-VersionNumber -Value $installedText
            Write-Aegis ('WinGet installed: {0}; selected channel: {1} ({2})' -f
                $installedText, $Channel, $release.tag_name) -Style Muted

            if ($installedVersion -ge $releaseVersion) {
                Write-Aegis 'WinGet is current for the selected channel.' -Style Success
                return
            }
        }

        try {
            Install-WinGetRelease -Release $release
        }
        catch {
            if ($Channel -eq 'Newest' -and $release.prerelease -and $pair.Stable) {
                Write-Aegis ('WinGet prerelease {0} could not be installed; falling back to stable {1}. {2}' -f
                    $release.tag_name, $pair.Stable.tag_name, $_.Exception.Message) -Style Warning
                $release = $pair.Stable
                if ($working) {
                    $installedText = ((& winget --version) | Out-String).Trim()
                    if ((ConvertTo-VersionNumber -Value $installedText) -ge
                        (ConvertTo-VersionNumber -Value $release.tag_name)) {
                        Write-Aegis 'Installed WinGet is at least as new as the stable release.' -Style Success
                        return
                    }
                }
                try {
                    Install-WinGetRelease -Release $release
                }
                catch {
                    Write-Aegis ('Stable WinGet fallback {0} failed; continuing with installed version. {1}' -f
                        $release.tag_name, $_.Exception.Message) -Style Warning
                    if ($working) {
                        return
                    }
                    throw
                }
            }
            else {
                throw
            }
        }
    }
    catch {
        if ($working) {
            Write-Aegis ('WinGet update check failed; continuing with installed version. {0}' -f
                $_.Exception.Message) -Style Warning
            return
        }
        throw
    }

    if (-not (Test-WinGet)) {
        throw 'WinGet is still unavailable after bootstrap.'
    }

    & winget source update --accept-source-agreements --disable-interactivity | Out-Null
}

function Add-AegisResult {
    param(
        [object]$Package,
        [ValidateSet('Installed', 'Current', 'Skipped', 'Failed', 'Planned')]
        [string]$Status,
        [int]$ExitCode = 0,
        [string]$Detail = ''
    )

    $script:Results.Add([pscustomobject]@{
        Id = $Package.Id
        Name = $Package.Name
        Category = $Package.Category
        Status = $Status
        ExitCode = $ExitCode
        Detail = $Detail
    })
}

function Get-WinGetPackageState {
    param(
        [string]$Id,
        [string]$Source = 'winget'
    )

    $null = & winget list --exact --id $Id --source $Source `
        --accept-source-agreements --disable-interactivity 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        return 'Installed'
    }

    # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND
    if ($exitCode -eq -1978335212) {
        return 'Absent'
    }

    throw "WinGet could not determine installed state for '$Id' (exit $exitCode)."
}

function Install-WinGetPackage {
    param(
        [object]$Package,
        [switch]$ForceInstall,
        [int]$Attempts
    )

    if ($DryRun) {
        Add-AegisResult -Package $Package -Status Planned
        return
    }

    $installedState = Get-WinGetPackageState -Id $Package.Id -Source $Package.Source
    $operation = if ($installedState -eq 'Installed' -and -not $ForceInstall) {
        'upgrade'
    }
    else {
        'install'
    }

    $arguments = @(
        $operation, '--exact', '--id', $Package.Id,
        '--source', $Package.Source,
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity',
        '--silent'
    )
    if ($ForceInstall) {
        $arguments += '--force'
    }

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Write-AegisLog -Message ('winget {0} {1} (attempt {2}/{3})' -f $operation, $Package.Id, $attempt, $Attempts)
        $output = & winget @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        Add-Content -LiteralPath $script:LogPath -Value $output -Encoding UTF8

        # WinGet uses these stable HRESULTs for installed/current/pinned states.
        $noChangeExitCodes = @(
            -1978335189,
            -1978335135,
            -1978334963,
            -1978334962,
            -1978335153
        )
        if ($noChangeExitCodes -contains $exitCode) {
            Add-AegisResult -Package $Package -Status Current -ExitCode $exitCode
            return
        }

        if ($exitCode -eq 0 -or $exitCode -eq 3010) {
            # 3010 is ERROR_SUCCESS_REBOOT_REQUIRED: the install succeeded but needs a restart.
            $script:RebootRequired = $script:RebootRequired -or ($exitCode -eq 3010)
            Add-AegisResult -Package $Package -Status Installed -ExitCode $exitCode
            return
        }

        if ($output -match 'reboot|restart') {
            $script:RebootRequired = $true
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds ([Math]::Min(2 * $attempt, 6))
        }
    }

    $escapePattern = [regex]::Escape([string][char]27) + '\[[0-?]*[ -/]*[@-~]'
    $cleanOutput = $output -replace $escapePattern, ''
    $lastLine = $cleanOutput -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1
    $lastLine = if ($null -eq $lastLine) { '' } else { $lastLine.Trim() }
    if ($lastLine.Length -gt 140) {
        $lastLine = $lastLine.Substring(0, 137) + '...'
    }
    $unsignedExitCode = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$exitCode), 0)
    $detail = 'WinGet exit 0x{0:X8}' -f $unsignedExitCode
    if ($lastLine) {
        $detail += ': ' + $lastLine
    }
    Add-AegisResult -Package $Package -Status Failed -ExitCode $exitCode -Detail $detail
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-AegisCommandLiteral {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return '$null'
    }

    return "'{0}'" -f ("$Value" -replace "'", "''")
}

function Format-AegisArguments {
    # Show -Profile, the documented alias, rather than the internal parameter name.
    $parts = @($script:AegisBoundParameters.GetEnumerator() |
        ForEach-Object { [pscustomobject]@{ Key = ($_.Key -replace '^AegisProfile$', 'Profile'); Value = $_.Value } } |
        Sort-Object Key | ForEach-Object {
            if ($_.Value -is [System.Management.Automation.SwitchParameter]) {
                '-{0}' -f $_.Key
            }
            else {
                '-{0} {1}' -f $_.Key, (@($_.Value) -join ',')
            }
        })
    if ($parts.Count -eq 0) {
        return '(none)'
    }
    return $parts -join ' '
}

function Start-AegisElevated {
    $enginePath = (Get-Process -Id $PID).Path
    if ($script:RunningFromFile) {
        $commandParts = @('&', (ConvertTo-AegisCommandLiteral -Value $PSCommandPath), '-Elevated')
    }
    else {
        $commandParts = @(
            '$aegisElevatedScript = (Invoke-RestMethod -UseBasicParsing -Uri',
            (ConvertTo-AegisCommandLiteral -Value $script:AegisSourceUrl),
            '); $aegisElevatedScript = $aegisElevatedScript.TrimStart([char]0xFEFF);',
            '& ([scriptblock]::Create($aegisElevatedScript)) -Elevated'
        )
    }

    # Share one log with the elevated window so this window can point at it afterwards.
    $forwarded = @{} + $script:AegisBoundParameters
    $forwarded['LogPath'] = $script:LogPath

    foreach ($entry in $forwarded.GetEnumerator()) {
        if ($entry.Key -eq 'Elevated') {
            continue
        }

        if ($entry.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($entry.Value.IsPresent) {
                $commandParts += '-{0}' -f $entry.Key
            }
            continue
        }

        $commandParts += '-{0}' -f $entry.Key
        if ($entry.Value -is [array]) {
            $commandParts += ConvertTo-AegisCommandLiteral -Value (($entry.Value | ForEach-Object { "$_" }) -join ',')
        }
        else {
            $commandParts += ConvertTo-AegisCommandLiteral -Value $entry.Value
        }
    }

    $command = $commandParts -join ' '
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    Show-AegisHeader
    Write-Aegis '  Administrator access is required once. AEGIS continues in a new window.' -Style Warning
    try {
        $process = Start-Process -FilePath $enginePath -Verb RunAs -Wait -PassThru `
            -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
    }
    catch {
        $nativeErrorCode = if ($_.Exception.PSObject.Properties['NativeErrorCode']) {
            $_.Exception.NativeErrorCode
        }
        else {
            0
        }
        if ($nativeErrorCode -eq 1223 -or $_.Exception.Message -match 'cancel') {
            Write-Aegis '  Administrator request cancelled. No installation was started.' -Style Warning
            return 0
        }
        throw
    }

    $exitCode = $process.ExitCode
    switch ($exitCode) {
        0 { Write-Aegis '  AEGIS finished successfully.' -Style Success }
        2 { Write-Aegis '  AEGIS finished, but one or more items failed.' -Style Warning }
        -1073741510 {
            Write-Aegis '  Elevated AEGIS was interrupted or its window was closed. Installation may be incomplete; run AEGIS again to continue.' -Style Warning
            return 2
        }
        default { Write-Aegis ('  AEGIS stopped with exit code {0}.' -f $exitCode) -Style Failure }
    }
    if (Test-Path -LiteralPath $script:LogPath) {
        Write-Aegis ('  LOG  {0}' -f $script:LogPath) -Style Muted
    }
    return $exitCode
}

function Install-WindowsFeaturePackage {
    param([object]$Package)

    if ($DryRun) {
        Add-AegisResult -Package $Package -Status Planned
        return
    }

    try {
        if (-not (Test-IsAdministrator)) {
            throw ('{0} requires administrator access, but the AEGIS session is not elevated.' -f $Package.Name)
        }

        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Package.FeatureName
        if ($feature.State -eq 'Enabled') {
            Add-AegisResult -Package $Package -Status Current
            return
        }

        $result = Enable-WindowsOptionalFeature -Online -FeatureName $Package.FeatureName `
            -All -NoRestart -ErrorAction Stop
        if ($result.RestartNeeded) {
            $script:RebootRequired = $true
        }
        Add-AegisResult -Package $Package -Status Installed
    }
    catch {
        Add-AegisResult -Package $Package -Status Failed -ExitCode 1 -Detail $_.Exception.Message
    }
}

function Show-InstallationPlan {
    param([object[]]$Packages)

    Write-Aegis ('  INSTALLATION PLAN - {0} ITEMS' -f $Packages.Count) -Style Accent
    Write-Host ''

    $width = Get-AegisWidth
    $separator = ' {0} ' -f (Get-AegisGlyph Dot)
    $categories = @($Packages | Select-Object -ExpandProperty Category -Unique)
    foreach ($category in $categories) {
        $members = @($Packages | Where-Object { $_.Category -eq $category })
        $label = '  {0,-22}{1,3}   ' -f $category.ToUpperInvariant(), $members.Count
        $indent = ' ' * $label.Length

        $lines = New-Object System.Collections.Generic.List[string]
        $current = ''
        foreach ($member in $members) {
            Write-AegisLog -Message ('PLAN  {0}  [{1}]' -f $member.Name, $member.Id)
            $chip = Get-AegisShortName -Package $member
            $candidate = if ($current) { $current + $separator + $chip } else { $chip }
            if ($current -and ($label.Length + $candidate.Length) -gt $width) {
                $lines.Add($current)
                $current = $chip
            }
            else {
                $current = $candidate
            }
        }
        $lines.Add($current)

        Write-Aegis $label -Style Secondary -NoNewline -SkipLog
        Write-Aegis $lines[0] -SkipLog
        for ($index = 1; $index -lt $lines.Count; $index++) {
            Write-Aegis ($indent + $lines[$index]) -SkipLog
        }
    }
    Write-Host ''
}

function Format-AegisDuration {
    param([TimeSpan]$Duration)

    if ($Duration.TotalMinutes -ge 1) {
        return '{0}m {1:D2}s' -f [int][Math]::Floor($Duration.TotalMinutes), $Duration.Seconds
    }
    return '{0}s' -f [int][Math]::Ceiling($Duration.TotalSeconds)
}

function Set-AegisTitle {
    param([string]$Text)

    if ([Console]::IsOutputRedirected) {
        return
    }
    try {
        $Host.UI.RawUI.WindowTitle = $Text
    }
    catch {
        # The window title is cosmetic.
    }
}

function Invoke-AegisDeployment {
    param([object[]]$Packages)

    $live = -not [Console]::IsOutputRedirected
    $total = $Packages.Count
    $digits = ([string]$total).Length
    $currentCategory = ''
    $index = 0

    foreach ($package in $Packages) {
        $index++
        if ($package.Category -ne $currentCategory) {
            $currentCategory = $package.Category
            Write-Host ''
            Write-Aegis ('  {0}' -f $currentCategory.ToUpperInvariant()) -Style Secondary
        }

        $counter = '{0}/{1}' -f ([string]$index).PadLeft($digits, '0'), $total
        $shortName = Get-AegisShortName -Package $package
        Set-AegisTitle -Text ('AEGIS  {0}  {1}' -f $counter, $package.Name)

        $pending = '  {0}  {1}  {2,-44} WORKING' -f (Get-AegisGlyph Pending), $counter, $shortName
        if ($live) {
            Write-Aegis $pending -Style Muted -NoNewline -SkipLog
        }

        $timer = [Diagnostics.Stopwatch]::StartNew()
        if ($package.Kind -eq 'WindowsFeature') {
            Install-WindowsFeaturePackage -Package $package
        }
        else {
            Install-WinGetPackage -Package $package -ForceInstall:$Force -Attempts $RetryCount
        }
        $timer.Stop()

        $result = $script:Results[$script:Results.Count - 1]
        $glyph = if ($result.Status -eq 'Failed') { Get-AegisGlyph Fail } else { Get-AegisGlyph Ok }
        $style = switch ($result.Status) {
            'Installed' { 'Success' }
            'Failed' { 'Failure' }
            default { 'Muted' }
        }
        $line = '  {0}  {1}  {2,-44} {3,-9} {4}' -f $glyph, $counter, $shortName,
            $result.Status.ToUpperInvariant(), (Format-AegisDuration -Duration $timer.Elapsed)

        if ($live) {
            Write-Host "`r" -NoNewline
            $line = $line.PadRight($pending.Length)
        }
        Write-Aegis $line -Style $style
        if ($result.Status -eq 'Failed' -and $result.Detail) {
            Write-Aegis ('         {0}' -f $result.Detail) -Style Failure
        }
    }
}

function Show-Summary {
    param([TimeSpan]$Elapsed)

    $counts = @{}
    foreach ($status in @('Installed', 'Current', 'Skipped', 'Failed', 'Planned')) {
        $counts[$status] = @($script:Results | Where-Object { $_.Status -eq $status }).Count
    }

    if (-not $Unattended -and -not [Console]::IsOutputRedirected) {
        Reset-AegisScreen
    }
    else {
        Write-Host ''
    }

    if ($counts.Planned -gt 0) {
        Write-Aegis '  PREVIEW COMPLETE' -Style Accent
        Write-Aegis ('  {0} ITEMS PLANNED  /  NOTHING WAS CHANGED' -f $counts.Planned) -Style Success
    }
    else {
        Write-Aegis '  DEPLOYMENT COMPLETE' -Style Accent
        Write-Aegis ('  {0} INSTALLED  /  {1} CURRENT  /  {2} FAILED  /  {3}' -f
            $counts.Installed, $counts.Current, $counts.Failed, (Format-AegisDuration -Duration $Elapsed)) `
            -Style $(if ($counts.Failed) { 'Warning' } else { 'Success' })
    }
    Write-Host ''

    $categories = @($script:Results | Select-Object -ExpandProperty Category -Unique)
    foreach ($category in $categories) {
        $members = @($script:Results | Where-Object { $_.Category -eq $category })
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($status in @('Installed', 'Current', 'Planned', 'Failed')) {
            $count = @($members | Where-Object { $_.Status -eq $status }).Count
            if ($count -gt 0) {
                $parts.Add(('{0} {1}' -f $count, $status.ToLowerInvariant()))
            }
        }
        $style = if (@($members | Where-Object { $_.Status -eq 'Failed' }).Count) {
            'Failure'
        }
        elseif (@($members | Where-Object { $_.Status -eq 'Installed' }).Count) {
            'Success'
        }
        else {
            'Muted'
        }
        Write-Aegis ('  {0,-24}{1}' -f $category.ToUpperInvariant(), ($parts -join ', ')) -Style $style
    }

    $failed = @($script:Results | Where-Object { $_.Status -eq 'Failed' })
    if ($failed.Count -gt 0) {
        Write-Host ''
        Write-Aegis '  NEEDS ATTENTION' -Style Failure
        foreach ($result in $failed) {
            Write-Aegis ('    {0}  {1}' -f (Get-AegisGlyph Fail), $result.Name) -Style Failure
            if ($result.Detail) {
                Write-Aegis ('       {0}' -f $result.Detail) -Style Muted
            }
        }
        Write-Aegis '  Run AEGIS again to retry; items that are already current are skipped quickly.' -Style Muted
    }

    if ($script:RebootRequired) {
        Write-Host ''
        Write-Aegis '  RESTART RECOMMENDED' -Style Warning
        Write-Aegis '  Finish your work and restart Windows to complete setup.' -Style Warning
    }
    Write-Host ''
    Write-Aegis ('  FULL LOG  {0}' -f $script:LogPath) -Style Muted
}

function Show-LogTail {
    param([int]$Lines = 15)

    if (-not (Test-Path -LiteralPath $script:LogPath)) {
        return
    }

    Write-Host ''
    Write-Aegis ('  LAST {0} LOG LINES' -f $Lines) -Style Accent -SkipLog
    foreach ($line in @(Get-Content -LiteralPath $script:LogPath -Tail $Lines)) {
        Write-Aegis ('  {0}' -f $line) -Style Muted -SkipLog
    }
}

function Read-NextAction {
    if (Test-AegisKeyInput) {
        Write-Host ''
        Write-Aegis '  ENTER  EXIT     M  MAIN MENU     L  OPEN LOG' -Style Muted -SkipLog
        while ($true) {
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                { $_ -in 'Enter', 'Escape', 'Q' } { return 'Exit' }
                'M' { return 'Menu' }
                'L' {
                    try {
                        Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $script:LogPath)
                    }
                    catch {
                        Write-Aegis '  Could not open the log.' -Style Warning -SkipLog
                    }
                }
            }
        }
    }

    Write-Host ''
    $answer = Read-Host '  ENTER  EXIT     M  MAIN MENU'
    if ("$answer".Trim() -match '^[Mm]$') {
        return 'Menu'
    }
    return 'Exit'
}

function Invoke-Aegis {
    try {
        if ($Help) {
            Show-AegisHelp
            return 0
        }

        if (-not $script:AegisIsWindows -and -not $ListPackages) {
            throw 'AEGIS requires Windows 10 or Windows 11.'
        }

        if (-not $Help -and -not $ListPackages -and -not $DryRun -and -not (Test-IsAdministrator)) {
            if ($Elevated) {
                throw 'Windows did not grant administrator access to the elevated AEGIS session.'
            }
            return (Start-AegisElevated)
        }

        Write-AegisLog -Message ('AEGIS {0} started. Arguments: {1}' -f
            $script:AegisVersion, (Format-AegisArguments)) -Level INFO

        # PowerShell's native executable boundary can deliver comma-separated
        # values as one string even when the parameter type is string[]. Make
        # the documented CLI form and programmatic array form equivalent.
        $script:IncludeGroup = @($IncludeGroup | ForEach-Object { "$_" -split ',' } |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $script:IncludePackage = @($IncludePackage | ForEach-Object { "$_" -split ',' } |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $script:ExcludePackage = @($ExcludePackage | ForEach-Object { "$_" -split ',' } |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })

        $validGroups = @($script:AegisGroups | ForEach-Object { $_.Key })
        foreach ($group in $IncludeGroup) {
            if ($validGroups -notcontains $group) {
                throw ('Unknown component supplied to -IncludeGroup: {0}. Valid components: {1}' -f
                    $group, ($validGroups -join ', '))
            }
        }

        $manifest = @(Get-AegisManifest)

        if ($ListPackages) {
            $manifest |
                Select-Object Category, Name, Id, Source, Kind, Architecture |
                Format-Table -AutoSize |
                Out-Host
            return 0
        }

        if ($AegisProfile -eq 'Interactive' -and $Unattended) {
            $script:AegisProfile = 'Recommended'
        }

        $interactive = -not $Unattended -and $AegisProfile -eq 'Interactive'
        if (-not $interactive) {
            Show-AegisHeader
        }

        if ($AegisProfile -in @('Modern', 'Legacy', 'Full')) {
            Write-Aegis ('  Profile {0} is now an alias for Recommended.' -f $AegisProfile) `
                -Style Muted
            $script:AegisProfile = 'Recommended'
        }

        $sessionHadFailure = $false

        while ($true) {
            if ($interactive) {
                $ids = Read-AegisSelection -Manifest $manifest
                if ($null -eq $ids) {
                    Write-Aegis '  Cancelled. Nothing was changed.' -Style Warning
                    return $(if ($sessionHadFailure) { 2 } else { 0 })
                }
                $selected = @(Get-SelectedPackages -Manifest $manifest -SelectedProfile 'Custom' `
                    -Groups @() -ExplicitPackages $ids -ExcludedPackages $ExcludePackage)

                Reset-AegisScreen
                Show-InstallationPlan -Packages $selected
                if (-not (Read-PlanConfirmation)) {
                    continue
                }
            }
            else {
                $selected = @(Get-SelectedPackages -Manifest $manifest -SelectedProfile $AegisProfile `
                    -Groups $IncludeGroup -ExplicitPackages $IncludePackage `
                    -ExcludedPackages $ExcludePackage)
                if ($selected.Count -eq 0) {
                    throw 'No packages were selected. Custom profile requires -IncludeGroup and/or -IncludePackage.'
                }
                Show-InstallationPlan -Packages $selected
                if (-not $Unattended -and -not $DryRun -and -not (Read-PlanConfirmation)) {
                    Write-Aegis '  Cancelled. Nothing was changed.' -Style Warning
                    return 0
                }
            }

            $timer = [Diagnostics.Stopwatch]::StartNew()
            if ($DryRun) {
                Write-Aegis '  Dry run: no system changes will be made.' -Style Warning
                foreach ($package in $selected) {
                    Add-AegisResult -Package $package -Status Planned
                }
            }
            else {
                if ($interactive) {
                    Reset-AegisScreen
                }
                Ensure-WinGet -Channel $WinGetChannel -SkipUpdate:$SkipWinGetUpdate
                Invoke-AegisDeployment -Packages $selected
            }
            $timer.Stop()
            Set-AegisTitle -Text 'AEGIS'

            Show-Summary -Elapsed $timer.Elapsed
            $failureCount = @($script:Results | Where-Object { $_.Status -eq 'Failed' }).Count
            if ($failureCount -gt 0) {
                $sessionHadFailure = $true
            }

            if (-not $interactive -or (Read-NextAction) -ne 'Menu') {
                return $(if ($sessionHadFailure) { 2 } else { 0 })
            }

            $script:Results = New-Object System.Collections.Generic.List[object]
            $script:RebootRequired = $false
        }
    }
    catch {
        try {
            Write-Aegis ('  FATAL  {0}' -f $_.Exception.Message) -Style Failure
            Write-AegisLog -Message $_.ScriptStackTrace -Level ERROR
            Show-LogTail
            Write-Aegis ('  FULL LOG  {0}' -f $script:LogPath) -Style Muted
        }
        catch {
            Write-Error $_
        }
        return 1
    }
}

$aegisExitCode = Invoke-Aegis
$global:LASTEXITCODE = $aegisExitCode
if ($script:RunningFromFile) {
    exit $aegisExitCode
}
