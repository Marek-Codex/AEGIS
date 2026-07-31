#requires -Version 5.1
<#
.SYNOPSIS
    AEGIS - Automated Essentials for Gaming Installation System.

.DESCRIPTION
    Installs curated Windows gaming runtimes and optional applications through
    WinGet. AEGIS is designed to run as a local script or through:

        irm <raw Install.ps1 URL> | iex

    Dry-run mode never installs packages, changes Windows features, or updates
    WinGet.
#>

[CmdletBinding()]
param(
    [Alias('Profile')]
    [ValidateSet('Interactive', 'Modern', 'Legacy', 'Full', 'Custom')]
    [string]$AegisProfile = 'Interactive',

    [ValidateSet(
        'Java', 'Utilities', 'Browsers', 'Launchers', 'Communication',
        'Capture', 'Monitoring', 'Modding'
    )]
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

$script:AegisVersion = '0.1.0'
$script:RunningFromFile = -not [string]::IsNullOrWhiteSpace($PSCommandPath)
$script:RebootRequired = $false
$script:Results = New-Object System.Collections.Generic.List[object]
$script:LogPath = $LogPath
$script:UseColor = -not $NoColor -and -not [Console]::IsOutputRedirected
$script:AegisIsWindows = $env:OS -eq 'Windows_NT'

if ($script:AegisIsWindows) {
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    }
    catch {
        # Output encoding is cosmetic; installation can continue.
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
    Write-Aegis 'AUTOMATED ESSENTIALS FOR GAMING INSTALLATION SYSTEM' -Style Muted -SkipLog
    Write-Aegis ('VERSION {0}' -f $script:AegisVersion) -Style Secondary -SkipLog
    Write-Host ''
}

function Show-AegisHelp {
    @'
AEGIS - Automated Essentials for Gaming Installation System

USAGE
  .\Install.ps1
  .\Install.ps1 -Profile Modern
  .\Install.ps1 -Profile Legacy -IncludeGroup Utilities,Java
  .\Install.ps1 -Profile Full -WinGetChannel Newest -Unattended
  .\Install.ps1 -Profile Custom -IncludePackage Microsoft.DirectX
  .\Install.ps1 -Profile Modern -DryRun

PROFILES
  Modern   Current gaming runtimes.
  Legacy   Modern baseline plus legacy compatibility runtimes.
  Full     Every curated runtime and compatibility component.
  Custom   Only packages supplied with -IncludePackage/-IncludeGroup.

OPTIONAL GROUPS
  Java, Utilities, Browsers, Launchers, Communication, Capture,
  Monitoring, Modding

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
        [string]$Architecture = 'Any'
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
    }
}

function Get-AegisManifest {
    @(
        # Modern baseline
        New-AegisPackage 'Microsoft.VCRedist.2015+.x86' 'Microsoft Visual C++ v14 Redistributable (x86)' 'Modern' @('Modern', 'Legacy', 'Full')
        New-AegisPackage 'Microsoft.VCRedist.2015+.x64' 'Microsoft Visual C++ v14 Redistributable (x64)' 'Modern' @('Modern', 'Legacy', 'Full') @() 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2015+.arm64' 'Microsoft Visual C++ v14 Redistributable (Arm64)' 'Modern' @('Modern', 'Legacy', 'Full') @() 'WinGet' '' 'arm64'
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.8' 'Microsoft .NET Desktop Runtime 8' 'Modern' @('Modern', 'Legacy', 'Full')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.10' 'Microsoft .NET Desktop Runtime 10' 'Modern' @('Modern', 'Legacy', 'Full')
        New-AegisPackage 'Microsoft.DirectX' 'DirectX End-User Runtime' 'Modern' @('Modern', 'Legacy', 'Full')
        New-AegisPackage 'CreativeTechnology.OpenAL' 'OpenAL' 'Modern' @('Modern', 'Legacy', 'Full')
        New-AegisPackage 'Microsoft.EdgeWebView2Runtime' 'Microsoft Edge WebView2 Runtime' 'Modern' @('Modern', 'Legacy', 'Full')

        # Legacy compatibility
        New-AegisPackage 'Microsoft.VCRedist.2005.x86' 'Microsoft Visual C++ 2005 Redistributable (x86)' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.VCRedist.2005.x64' 'Microsoft Visual C++ 2005 Redistributable (x64)' 'Legacy' @('Legacy', 'Full') @() 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2008.x86' 'Microsoft Visual C++ 2008 Redistributable (x86)' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.VCRedist.2008.x64' 'Microsoft Visual C++ 2008 Redistributable (x64)' 'Legacy' @('Legacy', 'Full') @() 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2010.x86' 'Microsoft Visual C++ 2010 Redistributable (x86)' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.VCRedist.2010.x64' 'Microsoft Visual C++ 2010 Redistributable (x64)' 'Legacy' @('Legacy', 'Full') @() 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2012.x86' 'Microsoft Visual C++ 2012 Redistributable (x86)' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.VCRedist.2012.x64' 'Microsoft Visual C++ 2012 Redistributable (x64)' 'Legacy' @('Legacy', 'Full') @() 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.VCRedist.2013.x86' 'Microsoft Visual C++ 2013 Redistributable (x86)' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.VCRedist.2013.x64' 'Microsoft Visual C++ 2013 Redistributable (x64)' 'Legacy' @('Legacy', 'Full') @() 'WinGet' '' 'x64'
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.3_1' 'Microsoft .NET Desktop Runtime 3.1' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.5' 'Microsoft .NET Desktop Runtime 5' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.6' 'Microsoft .NET Desktop Runtime 6' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.6.x86' 'Microsoft .NET Desktop Runtime 6 (x86)' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.7' 'Microsoft .NET Desktop Runtime 7' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.DotNet.DesktopRuntime.7.x86' 'Microsoft .NET Desktop Runtime 7 (x86)' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Microsoft.XNARedist' 'Microsoft XNA Framework Redistributable' 'Legacy' @('Legacy', 'Full')
        New-AegisPackage 'Nvidia.PhysX' 'NVIDIA PhysX System Software' 'Legacy' @('Legacy', 'Full') @() 'WinGet' '' 'x64'
        New-AegisPackage 'Nvidia.PhysXLegacy' 'NVIDIA PhysX Legacy' 'Legacy' @('Legacy', 'Full') @() 'WinGet' '' 'x64'
        New-AegisPackage 'Windows.DirectPlay' 'DirectPlay' 'Legacy' @('Legacy', 'Full') @() 'WindowsFeature' 'DirectPlay'

        # Optional groups
        New-AegisPackage 'Amazon.Corretto.25.JDK' 'Amazon Corretto 25 JDK' 'Java' @() @('Java')
        New-AegisPackage 'M2Team.NanaZip' 'NanaZip' 'Utilities' @() @('Utilities')
        New-AegisPackage 'Devolutions.UniGetUI' 'UniGetUI' 'Utilities' @() @('Utilities')
        New-AegisPackage 'Brave.Brave.Beta' 'Brave Beta' 'Browsers' @() @('Browsers')
        New-AegisPackage 'Valve.Steam' 'Steam' 'Launchers' @() @('Launchers')
        New-AegisPackage 'EpicGames.EpicGamesLauncher' 'Epic Games Launcher' 'Launchers' @() @('Launchers')
        New-AegisPackage 'GOG.Galaxy' 'GOG GALAXY' 'Launchers' @() @('Launchers')
        New-AegisPackage 'HeroicGamesLauncher.HeroicGamesLauncher' 'Heroic' 'Launchers' @() @('Launchers')
        New-AegisPackage 'Playnite.Playnite' 'Playnite' 'Launchers' @() @('Launchers')
        New-AegisPackage 'Discord.Discord' 'Discord' 'Communication' @() @('Communication')
        New-AegisPackage 'OBSProject.OBSStudio' 'OBS Studio' 'Capture' @() @('Capture')
        New-AegisPackage 'REALiX.HWiNFO' 'HWiNFO' 'Monitoring' @() @('Monitoring')
        New-AegisPackage 'TechPowerUp.GPU-Z' 'TechPowerUp GPU-Z' 'Monitoring' @() @('Monitoring')
        New-AegisPackage 'Guru3D.Afterburner' 'MSI Afterburner' 'Monitoring' @() @('Monitoring')
        New-AegisPackage 'PrismLauncher.PrismLauncher' 'Prism Launcher' 'Modding' @() @('Modding')
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
        'x64' { return $architecture -eq 'AMD64' }
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
        Modern       = 0
        Legacy       = 1
        Java         = 10
        Utilities    = 11
        Browsers     = 12
        Launchers    = 13
        Communication = 14
        Capture      = 15
        Monitoring   = 16
        Modding      = 17
    }

    return @($selected | Sort-Object `
        @{ Expression = { $categoryOrder[$_.Category] } }, Name -Unique)
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
        $top = [Console]::CursorTop
        $rowCount = $Choices.Count + 3
        $width = [Math]::Max(29, [Console]::WindowWidth - 1)

        try {
            [Console]::CursorVisible = $false
            while ($true) {
                [Console]::SetCursorPosition(0, $top)
                Write-Aegis $Prompt.PadRight($width) -Style Accent -SkipLog
                for ($index = 0; $index -lt $Choices.Count; $index++) {
                    $prefix = if ($index -eq $position) { '  > ' } else { '    ' }
                    $style = if ($index -eq $position) { 'Secondary' } else { 'Normal' }
                    Write-Aegis (($prefix + $Choices[$index]).PadRight($width)) `
                        -Style $style -SkipLog
                }
                Write-Aegis '  Arrows/WASD: move  Enter: select'.PadRight($width) `
                    -Style Muted -SkipLog
                Write-Aegis ''.PadRight($width) -SkipLog

                $key = [Console]::ReadKey($true)
                switch ($key.Key) {
                    'UpArrow' { $position = ($position - 1 + $Choices.Count) % $Choices.Count }
                    'W' { $position = ($position - 1 + $Choices.Count) % $Choices.Count }
                    'DownArrow' { $position = ($position + 1) % $Choices.Count }
                    'S' { $position = ($position + 1) % $Choices.Count }
                    'Enter' {
                        [Console]::SetCursorPosition(0, $top + $rowCount)
                        return $Choices[$position]
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
    while ($true) {
        $answer = Read-Host ('Select [{0}]' -f ($Default + 1))
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Choices[$Default]
        }

        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and
            $number -ge 1 -and $number -le $Choices.Count) {
            return $Choices[$number - 1]
        }

        Write-Aegis 'Invalid selection.' -Style Warning
    }
}

function Read-OptionalGroups {
    $groups = @('Java', 'Utilities', 'Browsers', 'Launchers', 'Communication', 'Capture', 'Monitoring', 'Modding')
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
        $top = [Console]::CursorTop
        $rowCount = $groups.Count + 4
        $width = [Math]::Max(39, [Console]::WindowWidth - 1)

        try {
            [Console]::CursorVisible = $false
            while ($true) {
                [Console]::SetCursorPosition(0, $top)
                $selectedCount = @($checked | Where-Object { $_ }).Count
                Write-Aegis ('OPTIONAL GROUPS - {0} SELECTED' -f $selectedCount).PadRight($width) `
                    -Style Accent -SkipLog

                for ($index = 0; $index -lt $groups.Count; $index++) {
                    $cursor = if ($index -eq $position) { '>' } else { ' ' }
                    $mark = if ($checked[$index]) { 'x' } else { ' ' }
                    $style = if ($index -eq $position) { 'Secondary' } else { 'Normal' }
                    Write-Aegis ('  {0} [{1}] {2}' -f $cursor, $mark, $groups[$index]).PadRight($width) `
                        -Style $style -SkipLog
                }

                Write-Aegis '  Arrows/WASD: move  Space: toggle'.PadRight($width) `
                    -Style Muted -SkipLog
                Write-Aegis '  A: all  N: none  Enter: continue'.PadRight($width) `
                    -Style Muted -SkipLog
                Write-Aegis ''.PadRight($width) -SkipLog

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
                        [Console]::SetCursorPosition(0, $top + $rowCount)
                        $selected = New-Object System.Collections.Generic.List[string]
                        for ($index = 0; $index -lt $groups.Count; $index++) {
                            if ($checked[$index]) {
                                $selected.Add($groups[$index])
                            }
                        }
                        return $selected.ToArray()
                    }
                }
            }
        }
        finally {
            [Console]::CursorVisible = $true
        }
    }

    Write-Aegis 'OPTIONAL GROUPS' -Style Accent
    for ($index = 0; $index -lt $groups.Count; $index++) {
        Write-Aegis ('  [{0}] {1}' -f ($index + 1), $groups[$index])
    }
    Write-Aegis 'Enter comma-separated numbers, or press Enter for none.' -Style Muted
    $answer = Read-Host 'Select'

    if ([string]::IsNullOrWhiteSpace($answer)) {
        return @()
    }

    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($token in ($answer -split ',')) {
        $number = 0
        if (-not [int]::TryParse($token.Trim(), [ref]$number) -or
            $number -lt 1 -or $number -gt $groups.Count) {
            throw "Invalid optional group selection: $token"
        }
        if (-not $selected.Contains($groups[$number - 1])) {
            $selected.Add($groups[$number - 1])
        }
    }
    return $selected.ToArray()
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
    param([string]$Id)

    $null = & winget list --exact --id $Id --source winget `
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

    $installedState = Get-WinGetPackageState -Id $Package.Id
    $operation = if ($installedState -eq 'Installed' -and -not $ForceInstall) {
        'upgrade'
    }
    else {
        'install'
    }

    $arguments = @(
        $operation, '--exact', '--id', $Package.Id,
        '--source', 'winget',
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

        if ($exitCode -eq 0) {
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

    $detail = ($output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
    Write-Aegis ('  FAILED  {0}' -f $Package.Name) -Style Failure
    Add-AegisResult -Package $Package -Status Failed -ExitCode $exitCode -Detail $detail
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-WindowsFeaturePackage {
    param([object]$Package)

    if ($DryRun) {
        Write-Aegis ('  PLAN  {0}' -f $Package.Name) -Style Accent
        Add-AegisResult -Package $Package -Status Planned
        return
    }

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Package.FeatureName
        if ($feature.State -eq 'Enabled') {
            Write-Aegis ('  CURRENT  {0}' -f $Package.Name) -Style Muted
            Add-AegisResult -Package $Package -Status Current
            return
        }

        if (-not (Test-IsAdministrator)) {
            if ($Unattended) {
                throw 'DirectPlay requires an elevated shell during unattended installation.'
            }

            Write-Aegis '  DirectPlay requires elevation. Approve the UAC prompt.' -Style Warning
            $dismPath = Join-Path $env:SystemRoot 'System32\dism.exe'
            $process = Start-Process -FilePath $dismPath -Verb RunAs -Wait -PassThru `
                -ArgumentList @(
                    '/Online',
                    ('/Enable-Feature'),
                    ('/FeatureName:{0}' -f $Package.FeatureName),
                    '/All',
                    '/NoRestart'
                )

            if ($process.ExitCode -eq 3010) {
                $script:RebootRequired = $true
            }
            elseif ($process.ExitCode -ne 0) {
                throw "Elevated DISM exited with code $($process.ExitCode)."
            }

            Write-Aegis ('  DONE  {0}' -f $Package.Name) -Style Success
            Add-AegisResult -Package $Package -Status Installed
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

    Write-Host ''
    Write-Aegis 'SUMMARY' -Style Accent
    Write-Aegis ('  Installed  {0}' -f $counts.Installed) -Style Success
    Write-Aegis ('  Current    {0}' -f $counts.Current) -Style Muted
    Write-Aegis ('  Planned    {0}' -f $counts.Planned) -Style Accent
    Write-Aegis ('  Failed     {0}' -f $counts.Failed) -Style $(if ($counts.Failed) { 'Failure' } else { 'Muted' })

    if ($counts.Failed -gt 0) {
        Write-Host ''
        foreach ($result in ($script:Results | Where-Object { $_.Status -eq 'Failed' })) {
            Write-Aegis ('  {0}: {1}' -f $result.Name, $result.Detail) -Style Failure
        }
    }

    if ($script:RebootRequired) {
        Write-Aegis 'A restart is recommended.' -Style Warning
    }
    Write-Aegis ('Log: {0}' -f $script:LogPath) -Style Muted
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

        Write-AegisLog -Message ('AEGIS {0} started. Arguments: {1}' -f
            $script:AegisVersion, ($MyInvocation.Line)) -Level INFO
        Show-AegisHeader

        $manifest = @(Get-AegisManifest)

        if ($ListPackages) {
            $manifest |
                Select-Object Category, Name, Id, Kind, Architecture |
                Format-Table -AutoSize |
                Out-Host
            return 0
        }

        if ($AegisProfile -eq 'Interactive') {
            if ($Unattended) {
                $script:AegisProfile = 'Modern'
            }
            else {
                $script:AegisProfile = Read-MenuChoice -Prompt 'INSTALLATION PROFILE' `
                    -Choices @('Modern', 'Legacy', 'Full', 'Custom') -Default 0
            }
        }

        if (-not $Unattended -and $IncludeGroup.Count -eq 0) {
            $script:IncludeGroup = @(Read-OptionalGroups)
        }

        $selected = @(Get-SelectedPackages -Manifest $manifest -SelectedProfile $AegisProfile `
            -Groups $IncludeGroup -ExplicitPackages $IncludePackage `
            -ExcludedPackages $ExcludePackage)

        if ($selected.Count -eq 0) {
            throw 'No packages were selected.'
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

        $currentCategory = ''
        foreach ($package in $selected) {
            if ($package.Category -ne $currentCategory) {
                $currentCategory = $package.Category
                Write-Host ''
                Write-Aegis $currentCategory.ToUpperInvariant() -Style Secondary
            }

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
            return 2
        }
        return 0
    }
    catch {
        try {
            Write-Aegis ('FATAL  {0}' -f $_.Exception.Message) -Style Failure
            Write-AegisLog -Message $_.ScriptStackTrace -Level ERROR
            Write-Aegis ('Log: {0}' -f $script:LogPath) -Style Muted
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
