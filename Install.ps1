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
    [string]$WinGetChannel = 'Stable',

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

$script:AegisVersion = '0.2.0'
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
    $rule = if ($script:UseUnicode) { [string][char]0x2501 } else { '=' }
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
  .\Install.ps1
  .\Install.ps1 -Profile Recommended -Unattended
  .\Install.ps1 -Profile Custom -IncludeGroup VC++,DotNet,AspNet
  .\Install.ps1 -Profile Custom -IncludePackage Microsoft.DirectX
  .\Install.ps1 -Profile Recommended -DryRun

PROFILES
  Recommended  Complete curated gaming prerequisite stack.
  Custom       Only components/packages supplied explicitly.

CUSTOM COMPONENTS
  VC++, DotNet, AspNet, Gaming, Essentials, Java, Workbench

COMPATIBILITY
  Modern, Legacy, and Full remain accepted as aliases for Recommended.

WINGET CHANNELS
  Stable   GitHub's latest stable WinGet release.
  Preview  Most recently published WinGet prerelease.
  Newest   Most recently published release, stable or prerelease.

EXIT CODES
  0  Completed successfully.
  1  Fatal bootstrap or configuration error.
  2  One or more selected items failed.
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
        'Power User Workbench'  = 6
    }

    $architectureOrder = @{
        Any   = 0
        x64   = 1
        arm64 = 2
    }

    return @($selected | Sort-Object `
        @{ Expression = { $categoryOrder[$_.Category] } }, `
        @{ Expression = { $_.Name -replace ' \((x86|x64|Arm64)\)$', '' } }, `
        @{ Expression = { $architectureOrder[$_.Architecture] } }, Name -Unique)
}

function Read-MenuChoice {
    param(
        [string]$Prompt,
        [string[]]$Choices,
        [int]$Default = 0
    )

    $useInteractiveKeys = $false
    try {
        $useInteractiveKeys = -not [Console]::IsInputRedirected -and
            -not [Console]::IsOutputRedirected -and
            [Console]::WindowWidth -ge 30
    }
    catch {
        $useInteractiveKeys = $false
    }

    if ($useInteractiveKeys) {
        $position = $Default

        try {
            [Console]::CursorVisible = $false
            while ($true) {
                [Console]::Clear()
                Show-AegisHeader
                $width = [Math]::Max(29, [Math]::Min(68, [Console]::WindowWidth - 2))
                Write-Aegis ('  {0}' -f $Prompt) -Style Accent -SkipLog
                Write-Host ''
                for ($index = 0; $index -lt $Choices.Count; $index++) {
                    $activeMarker = if ($script:UseUnicode) { [string][char]0x25B8 } else { '>' }
                    $prefix = if ($index -eq $position) { '  ' + $activeMarker } else { '   ' }
                    $style = if ($index -eq $position) { 'Secondary' } else { 'Normal' }
                    $parts = @($Choices[$index] -split '\s+//\s+', 2)
                    Write-Aegis ('{0}  {1:D2}  {2}' -f $prefix, ($index + 1), $parts[0].ToUpperInvariant()) `
                        -Style $style -SkipLog
                    if ($parts.Count -gt 1) {
                        Write-Aegis ('          {0}' -f $parts[1]) -Style Muted -SkipLog
                    }
                    if ($index -lt ($Choices.Count - 1)) {
                        Write-Host ''
                    }
                }
                Write-Host ''
                Write-Aegis '  UP/DOWN  MOVE     ENTER  SELECT     0  CANCEL' -Style Muted -SkipLog

                $key = [Console]::ReadKey($true)
                switch ($key.Key) {
                    'UpArrow' { $position = ($position - 1 + $Choices.Count) % $Choices.Count }
                    'W' { $position = ($position - 1 + $Choices.Count) % $Choices.Count }
                    'DownArrow' { $position = ($position + 1) % $Choices.Count }
                    'S' { $position = ($position + 1) % $Choices.Count }
                    'Enter' {
                        [Console]::Clear()
                        Show-AegisHeader
                        return $Choices[$position]
                    }
                    'D0' {
                        [Console]::Clear()
                        Show-AegisHeader
                        return $null
                    }
                    'NumPad0' {
                        [Console]::Clear()
                        Show-AegisHeader
                        return $null
                    }
                    default {
                        Write-Aegis '  Unrecognized key.'.PadRight($width) -Style Warning -SkipLog
                        Start-Sleep -Milliseconds 500
                    }
                }
            }
        }
        finally {
            [Console]::CursorVisible = $true
        }
    }

    Write-Aegis $Prompt -Style Accent
    for ($index = 0; $index -lt $Choices.Count; $index++) {
        $marker = if ($index -eq $Default) { '*' } else { ' ' }
        Write-Aegis ('  [{0}] {1} {2}' -f ($index + 1), $marker, $Choices[$index]) -Style Normal
    }
    Write-Aegis '  [0]   Cancel' -Style Normal
    while ($true) {
        $answer = Read-Host ('Select [{0}]' -f ($Default + 1))
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Choices[$Default]
        }

        if ($answer.Trim() -eq '0') {
            return $null
        }

        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and
            $number -ge 1 -and $number -le $Choices.Count) {
            return $Choices[$number - 1]
        }

        Write-Aegis 'Invalid selection.' -Style Warning
    }
}

function Read-CustomComponents {
    $groups = @('VC++', 'DotNet', 'AspNet', 'Gaming', 'Essentials', 'Java', 'Workbench')
    $labels = @(
        'VC++ Redistributables (x86 + native 64-bit)'
        '.NET Desktop Runtimes'
        'ASP.NET Core Runtimes'
        'Gaming Compatibility (DirectX, XNA, OpenAL, WebView2, PhysX, DirectPlay)'
        'Essentials (NanaZip + current PowerShell)'
        'Java (Amazon Corretto JDK)'
        'Power User Workbench [OPTIONAL / PRE-RELEASE SOFTWARE]'
    )
    $useInteractiveKeys = $false
    try {
        $useInteractiveKeys = -not [Console]::IsInputRedirected -and
            -not [Console]::IsOutputRedirected -and
            [Console]::WindowWidth -ge 40
    }
    catch {
        $useInteractiveKeys = $false
    }

    if ($useInteractiveKeys) {
        $position = 0
        $checked = New-Object 'bool[]' $groups.Count
        for ($index = 0; $index -lt 6; $index++) {
            $checked[$index] = $true
        }

        try {
            [Console]::CursorVisible = $false
            while ($true) {
                [Console]::Clear()
                Show-AegisHeader
                $selectedCount = @($checked | Where-Object { $_ }).Count
                Write-Aegis '  CUSTOM DEPLOYMENT' -Style Accent -SkipLog
                Write-Aegis ('  {0} OF {1} COMPONENT FAMILIES ARMED' -f $selectedCount, $groups.Count) `
                    -Style Muted -SkipLog
                Write-Host ''

                for ($index = 0; $index -lt $groups.Count; $index++) {
                    $cursor = if ($index -eq $position) {
                        if ($script:UseUnicode) { [string][char]0x25B8 } else { '>' }
                    }
                    else { ' ' }
                    $mark = if ($checked[$index]) { '+' } else { '-' }
                    $style = if ($index -eq $position) { 'Secondary' } else { 'Normal' }
                    Write-Aegis ('  {0}  [{1}]  {2}' -f $cursor, $mark, $labels[$index]) `
                        -Style $style -SkipLog
                }

                Write-Host ''
                Write-Aegis '  UP/DOWN  MOVE     SPACE  TOGGLE     ENTER  CONTINUE' -Style Muted -SkipLog
                Write-Aegis '  A  ALL            N  NONE         0  BACK' -Style Muted -SkipLog

                $key = [Console]::ReadKey($true)
                switch ($key.Key) {
                    'UpArrow' { $position = ($position - 1 + $groups.Count) % $groups.Count }
                    'W' { $position = ($position - 1 + $groups.Count) % $groups.Count }
                    'DownArrow' { $position = ($position + 1) % $groups.Count }
                    'S' { $position = ($position + 1) % $groups.Count }
                    'Spacebar' { $checked[$position] = -not $checked[$position] }
                    'A' {
                        for ($index = 0; $index -lt $checked.Count; $index++) {
                            $checked[$index] = $true
                        }
                    }
                    'N' {
                        for ($index = 0; $index -lt $checked.Count; $index++) {
                            $checked[$index] = $false
                        }
                    }
                    'Enter' {
                        [Console]::Clear()
                        Show-AegisHeader
                        $selected = New-Object System.Collections.Generic.List[string]
                        for ($index = 0; $index -lt $groups.Count; $index++) {
                            if ($checked[$index]) {
                                $selected.Add($groups[$index])
                            }
                        }
                        return ,$selected.ToArray()
                    }
                    'D0' {
                        [Console]::Clear()
                        Show-AegisHeader
                        return $null
                    }
                    'NumPad0' {
                        [Console]::Clear()
                        Show-AegisHeader
                        return $null
                    }
                    default {
                        Write-Aegis '  Unrecognized key.'.PadRight($width) -Style Warning -SkipLog
                        Start-Sleep -Milliseconds 500
                    }
                }
            }
        }
        finally {
            [Console]::CursorVisible = $true
        }
    }

    Write-Aegis 'CUSTOMIZE' -Style Accent
    for ($index = 0; $index -lt $groups.Count; $index++) {
        $defaultMarker = if ($index -lt 5) { ' [default]' } else { '' }
        Write-Aegis ('  [{0}] {1}{2}' -f ($index + 1), $labels[$index], $defaultMarker)
    }
    Write-Aegis '  [0] Back to profile selection' -Style Normal
    Write-Aegis 'Enter comma-separated numbers, 0 to go back, or press Enter for defaults.' -Style Muted
    $answer = Read-Host 'Select'

    if ([string]::IsNullOrWhiteSpace($answer)) {
        return ,$groups[0..4]
    }

    if ($answer.Trim() -eq '0') {
        return $null
    }

    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($token in ($answer -split ',')) {
        $number = 0
        if (-not [int]::TryParse($token.Trim(), [ref]$number) -or
            $number -lt 1 -or $number -gt $groups.Count) {
            throw "Invalid component selection: $token"
        }
        if (-not $selected.Contains($groups[$number - 1])) {
            $selected.Add($groups[$number - 1])
        }
    }
    return ,$selected.ToArray()
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

    $headers = @{
        'User-Agent' = 'AEGIS-Windows-Gaming-Installer'
        'Accept' = 'application/vnd.github+json'
    }

    if ($env:GITHUB_TOKEN) {
        $headers.Authorization = 'Bearer {0}' -f $env:GITHUB_TOKEN
    }

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
        $release = Get-WinGetRelease -Channel $Channel
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

        Install-WinGetRelease -Release $release
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
        Write-Aegis ('  PLAN  {0}' -f $Package.Name) -Style Accent
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
        Write-Aegis ('  [{0}/{1}] {2}' -f $attempt, $Attempts, $Package.Name) -Style Accent
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
            Write-Aegis ('  CURRENT  {0}' -f $Package.Name) -Style Muted
            Add-AegisResult -Package $Package -Status Current -ExitCode $exitCode
            return
        }

        if ($exitCode -eq 0 -or $exitCode -eq 3010) {
            # 3010 is ERROR_SUCCESS_REBOOT_REQUIRED: the install succeeded but needs a restart.
            $script:RebootRequired = $script:RebootRequired -or ($exitCode -eq 3010)
            Write-Aegis ('  DONE  {0}' -f $Package.Name) -Style Success
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
    Write-Aegis ('  FAILED  {0}' -f $Package.Name) -Style Failure
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

function Start-AegisElevated {
    $enginePath = (Get-Process -Id $PID).Path
    if ($script:RunningFromFile) {
        $commandParts = @('&', (ConvertTo-AegisCommandLiteral -Value $PSCommandPath), '-Elevated')
    }
    else {
        $commandParts = @(
            '& ([scriptblock]::Create((Invoke-RestMethod -UseBasicParsing -Uri',
            (ConvertTo-AegisCommandLiteral -Value $script:AegisSourceUrl),
            ')))',
            '-Elevated'
        )
    }

    foreach ($entry in $script:AegisBoundParameters.GetEnumerator()) {
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
    Write-Aegis 'Administrator access is required once for the complete installation.' -Style Warning
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
            Write-Aegis 'Administrator request cancelled. No installation was started.' -Style Warning
            return 0
        }
        throw
    }
    return $process.ExitCode
}

function Install-WindowsFeaturePackage {
    param([object]$Package)

    if ($DryRun) {
        Write-Aegis ('  PLAN  {0}' -f $Package.Name) -Style Accent
        Add-AegisResult -Package $Package -Status Planned
        return
    }

    try {
        if (-not (Test-IsAdministrator)) {
            throw ('{0} requires administrator access, but the AEGIS session is not elevated.' -f $Package.Name)
        }

        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Package.FeatureName
        if ($feature.State -eq 'Enabled') {
            Write-Aegis ('  CURRENT  {0}' -f $Package.Name) -Style Muted
            Add-AegisResult -Package $Package -Status Current
            return
        }

        $result = Enable-WindowsOptionalFeature -Online -FeatureName $Package.FeatureName `
            -All -NoRestart -ErrorAction Stop
        if ($result.RestartNeeded) {
            $script:RebootRequired = $true
        }
        Write-Aegis ('  DONE  {0}' -f $Package.Name) -Style Success
        Add-AegisResult -Package $Package -Status Installed
    }
    catch {
        Write-Aegis ('  FAILED  {0}' -f $Package.Name) -Style Failure
        Add-AegisResult -Package $Package -Status Failed -ExitCode 1 -Detail $_.Exception.Message
    }
}

function Show-InstallationPlan {
    param([object[]]$Packages)

    Write-Aegis ('INSTALLATION PLAN - {0} ITEMS' -f $Packages.Count) -Style Accent
    $currentCategory = ''
    foreach ($package in $Packages) {
        if ($package.Category -ne $currentCategory) {
            $currentCategory = $package.Category
            Write-Aegis ('  {0}' -f $currentCategory.ToUpperInvariant()) -Style Secondary
        }
        Write-Aegis ('    {0}' -f $package.Name)
    }
    Write-Host ''
}

function Show-Summary {
    $counts = @{}
    foreach ($status in @('Installed', 'Current', 'Skipped', 'Failed', 'Planned')) {
        $counts[$status] = @($script:Results | Where-Object { $_.Status -eq $status }).Count
    }

    $interactiveDisplay = -not $Unattended -and -not [Console]::IsOutputRedirected
    if ($interactiveDisplay) {
        [Console]::Clear()
        Show-AegisHeader
    }
    else {
        Write-Host ''
    }

    Write-Aegis '  DEPLOYMENT COMPLETE' -Style Accent
    Write-Aegis ('  {0} INSTALLED  /  {1} CURRENT  /  {2} FAILED' -f `
        $counts.Installed, $counts.Current, $counts.Failed) `
        -Style $(if ($counts.Failed) { 'Warning' } else { 'Success' })

    $currentCategory = ''
    foreach ($result in $script:Results) {
        if ($result.Category -ne $currentCategory) {
            $currentCategory = $result.Category
            Write-Host ''
            Write-Aegis ('  {0}' -f $currentCategory.ToUpperInvariant()) -Style Secondary
        }

        $statusStyle = switch ($result.Status) {
            'Installed' { 'Success' }
            'Failed' { 'Failure' }
            'Planned' { 'Accent' }
            default { 'Muted' }
        }
        Write-Aegis ('    {0,-9} {1}' -f $result.Status.ToUpperInvariant(), $result.Name) `
            -Style $statusStyle
        if ($result.Status -eq 'Failed' -and $result.Detail) {
            Write-Aegis ('              {0}' -f $result.Detail) -Style Failure
        }
    }

    if ($script:RebootRequired) {
        Write-Host ''
        Write-Aegis '  RESTART RECOMMENDED' -Style Warning
        Write-Aegis '  Finish your work and restart Windows to complete setup.' -Style Warning
    }
    Write-Host ''
    Write-Aegis ('  FULL LOG  {0}' -f $script:LogPath) -Style Muted
}

function Show-FinalLog {
    if (-not (Test-Path -LiteralPath $script:LogPath)) {
        return
    }

    $lines = @(Get-Content -LiteralPath $script:LogPath)
    $maxLines = 300
    $shown = if ($lines.Count -gt $maxLines) { $lines[($lines.Count - $maxLines)..($lines.Count - 1)] } else { $lines }

    Write-Host ''
    Write-Aegis ('FINAL INSTALL LOG ({0})' -f $script:LogPath) -Style Accent -SkipLog
    if ($lines.Count -gt $maxLines) {
        Write-Aegis ('  ...showing last {0} of {1} lines...' -f $maxLines, $lines.Count) -Style Muted -SkipLog
    }
    foreach ($line in $shown) {
        Write-Aegis ('  {0}' -f $line) -Style Muted -SkipLog
    }
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
            $script:AegisVersion, ($MyInvocation.Line)) -Level INFO
        Show-AegisHeader

        # PowerShell's native executable boundary can deliver comma-separated
        # values as one string even when the parameter type is string[]. Make
        # the documented CLI form and programmatic array form equivalent.
        $script:IncludeGroup = @($IncludeGroup | ForEach-Object { "$_" -split ',' } |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $script:IncludePackage = @($IncludePackage | ForEach-Object { "$_" -split ',' } |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $script:ExcludePackage = @($ExcludePackage | ForEach-Object { "$_" -split ',' } |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })

        $validGroups = @('VC++', 'DotNet', 'AspNet', 'Gaming', 'Essentials', 'Java', 'Workbench')
        foreach ($group in $IncludeGroup) {
            if ($validGroups -notcontains $group) {
                throw "Unknown component supplied to -IncludeGroup: $group"
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

        if ($AegisProfile -in @('Modern', 'Legacy', 'Full')) {
            Write-Aegis ('Profile {0} is now an alias for Recommended.' -f $AegisProfile) `
                -Style Muted
            $script:AegisProfile = 'Recommended'
        }

        $sessionHadFailure = $false

        while ($true) {
            $selected = @()

            if (-not $Unattended -and $AegisProfile -eq 'Interactive') {
                while ($true) {
                    $action = Read-MenuChoice -Prompt 'WHAT WOULD YOU LIKE TO DO?' `
                        -Choices @(
                            'Install recommended  // complete 40-item prerequisite stack'
                            'Customize            // choose component families'
                            'Exit'
                        ) -Default 0
                    if ($null -eq $action -or $action -eq 'Exit') {
                        Write-Aegis 'Cancelled.' -Style Warning
                        return 0
                    }

                    if ($action -like 'Install recommended*') {
                        $script:AegisProfile = 'Recommended'
                        $script:IncludeGroup = @()
                    }
                    else {
                        $script:AegisProfile = 'Custom'
                        $chosenGroups = Read-CustomComponents
                        if ($null -eq $chosenGroups) {
                            $script:AegisProfile = 'Interactive'
                            continue
                        }
                        $script:IncludeGroup = @($chosenGroups)
                    }

                    $selected = @(Get-SelectedPackages -Manifest $manifest -SelectedProfile $AegisProfile `
                        -Groups $IncludeGroup -ExplicitPackages $IncludePackage `
                        -ExcludedPackages $ExcludePackage)

                    if ($selected.Count -gt 0) {
                        break
                    }

                    Write-Aegis 'Select at least one component. Choose again.' `
                        -Style Warning
                }
            }
            else {
                $selected = @(Get-SelectedPackages -Manifest $manifest -SelectedProfile $AegisProfile `
                    -Groups $IncludeGroup -ExplicitPackages $IncludePackage `
                    -ExcludedPackages $ExcludePackage)
            }

            if ($selected.Count -eq 0) {
                throw 'No packages were selected. Custom profile requires -IncludeGroup and/or -IncludePackage.'
            }

            Show-InstallationPlan -Packages $selected

            if (-not $Unattended -and -not $DryRun) {
                $confirmation = Read-Host 'Continue? [Y/n]'
                if ($confirmation -match '^[Nn]') {
                    Write-Aegis 'Cancelled.' -Style Warning
                    return 0
                }
            }

            if ($DryRun) {
                Write-Aegis 'Dry run: no system changes will be made.' -Style Warning
            }
            else {
                Ensure-WinGet -Channel $WinGetChannel -SkipUpdate:$SkipWinGetUpdate
            }

            $categories = @($selected | Select-Object -ExpandProperty Category -Unique)
            $stageNumber = 0
            $packageNumber = 0
            $packagesInStage = 0
            $currentCategory = ''
            foreach ($package in $selected) {
                if ($package.Category -ne $currentCategory) {
                    $currentCategory = $package.Category
                    $stageNumber++
                    $packageNumber = 0
                    $packagesInStage = @($selected | Where-Object { $_.Category -eq $currentCategory }).Count
                    if (-not $Unattended -and -not [Console]::IsOutputRedirected) {
                        [Console]::Clear()
                        Show-AegisHeader
                    }
                    else {
                        Write-Host ''
                    }
                    Write-Aegis ('  STAGE {0:D2} / {1:D2}' -f $stageNumber, $categories.Count) `
                        -Style Muted
                    Write-Aegis ('  {0}' -f $currentCategory.ToUpperInvariant()) -Style Secondary
                    Write-Host ''
                }

                $packageNumber++
                Write-Aegis ('  PACKAGE {0:D2} / {1:D2}' -f $packageNumber, $packagesInStage) `
                    -Style Muted

                if ($package.Kind -eq 'WindowsFeature') {
                    Install-WindowsFeaturePackage -Package $package
                }
                else {
                    Install-WinGetPackage -Package $package -ForceInstall:$Force -Attempts $RetryCount
                }
            }

            Show-Summary
            $failureCount = @($script:Results | Where-Object { $_.Status -eq 'Failed' }).Count
            if ($failureCount -gt 0) {
                $sessionHadFailure = $true
            }

            if ($Unattended) {
                Show-FinalLog
                return $(if ($failureCount -gt 0) { 2 } else { 0 })
            }

            Write-Host ''
            $nextAction = Read-Host '  ENTER  EXIT     M  MAIN MENU'
            if ($nextAction.Trim() -notmatch '^[Mm]$') {
                return $(if ($sessionHadFailure) { 2 } else { 0 })
            }

            $script:Results = New-Object System.Collections.Generic.List[object]
            $script:RebootRequired = $false
            $script:AegisProfile = 'Interactive'
            $script:IncludeGroup = @()
        }
    }
    catch {
        try {
            Write-Aegis ('FATAL  {0}' -f $_.Exception.Message) -Style Failure
            Write-AegisLog -Message $_.ScriptStackTrace -Level ERROR
            Write-Aegis ('Log: {0}' -f $script:LogPath) -Style Muted
            Show-FinalLog
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
