$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'Install.ps1'
$batch = Join-Path $root 'Install.bat'
$readme = Join-Path $root 'README.md'
$enginePath = (Get-Process -Id $PID).Path

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

Write-Host 'Parsing PowerShell syntax...'
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $installer,
    [ref]$tokens,
    [ref]$errors
)
Assert-True ($errors.Count -eq 0) (($errors | ForEach-Object Message) -join '; ')

function Invoke-AegisDryRun {
    param([string[]]$Arguments)

    $logPath = Join-Path ([IO.Path]::GetTempPath()) ('AEGIS-validate-{0}.log' -f [guid]::NewGuid().ToString('N'))
    $output = & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $installer @Arguments -DryRun -Unattended -NoColor -LogPath $logPath 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $log = if (Test-Path -LiteralPath $logPath) { Get-Content -Raw -LiteralPath $logPath } else { '' }
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Output = $output; Log = $log; ExitCode = $exitCode }
}

Write-Host 'Checking required files...'
Assert-True (Test-Path -LiteralPath $batch) 'Install.bat is missing.'
Assert-True (Test-Path -LiteralPath $readme) 'README.md is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $root 'LICENSE')) 'LICENSE is missing.'

Write-Host 'Checking clean-room markers and publication URLs...'
$installerText = Get-Content -Raw -LiteralPath $installer
$batchText = Get-Content -Raw -LiteralPath $batch
$readmeText = Get-Content -Raw -LiteralPath $readme
Assert-True ($installerText -match 'Automated Essentials for Gaming Installation System') 'Expansion is missing.'
Assert-True ($installerText -notmatch 'harryeffinpotter') 'Upstream owner leaked into implementation.'
Assert-True ($batchText -match 'Marek-Codex/AEGIS') 'BAT publication URL is incorrect.'
Assert-True ($readmeText -match 'Marek-Codex/AEGIS') 'README publication URL is incorrect.'
Assert-True ($batchText -match 'github\.com/Marek-Codex/AEGIS/raw/refs/heads/main') `
    'BAT does not use the fresh GitHub branch endpoint.'
Assert-True ($readmeText -match 'github\.com/Marek-Codex/AEGIS/raw/refs/heads/main/Install\.ps1') `
    'README one-liner does not use the fresh GitHub branch endpoint.'
Assert-True ($readmeText -match 'PC-Gaming-Redists') 'Conceptual inspiration credit is missing.'
Assert-True ($readmeText -match 'clean-room implementation') 'Clean-room statement is missing.'
Assert-True ($installerText -notmatch 'No available upgrade found') 'Localized WinGet parsing returned.'
Assert-True ($installerText -match 'APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND') 'Installed-state exit code is missing.'
Assert-True ($installerText -match 'Start-Process.+-Verb RunAs') 'Single-session elevation helper is missing.'
Assert-True ($installerText -match '-not \$Help -and -not \$ListPackages -and -not \$DryRun') `
    'Read-only modes are not excluded from elevation.'
Assert-True ($installerText -match '\$PID') 'Default log path is not process-unique.'
Assert-True ($installerText -notmatch 'SetCursorPosition') `
    'Interactive menus use fragile absolute cursor positioning.'
Assert-True ($installerText -match '\[Console\]::BackgroundColor = \[ConsoleColor\]::Black') `
    'Interactive elevated consoles are not normalized to the AEGIS black background.'
Assert-True ($installerText -match "Read-Host '  ENTER  EXIT     M  MAIN MENU'") `
    'Completion screen does not preserve its results while prompting for the next action.'
Assert-True ($installerText -match 'WORKING') 'Live per-package progress line is missing.'
Assert-True ($installerText -notmatch 'function Show-FinalLog') `
    'The full log is dumped to the console again; show its path instead.'
Assert-True ($installerText -match 'RESTART RECOMMENDED') `
    'Prominent restart guidance is missing.'
Assert-True ($installerText.Contains("[string]`$WinGetChannel = 'Newest'")) `
    'WinGet does not default to the newest stable-or-preview release.'
Assert-True ($installerText -match 'Assert-ReleaseAssetHash') `
    'WinGet bootstrap does not verify the published SHA-256 digests.'
Assert-True ($installerText -match 'prerelease lookup failed; trying the latest stable release') `
    'WinGet does not fall back to stable if prerelease discovery fails.'
Assert-True ($installerText -match "'WindowsFeature' 'NetFx3'") `
    '.NET Framework 3.5 is not modeled as an optional Windows feature.'
Assert-True ($installerText -match 'Administrator request cancelled') `
    'UAC cancellation is not handled cleanly.'
Assert-True ($installerText -match 'Elevated AEGIS was interrupted or its window was closed') `
    'Closing or interrupting the elevated window is not reported clearly.'
Assert-True ($installerText -match 'Items failed, or elevated setup was interrupted') `
    'Built-in help does not explain the elevated interruption exit code.'
Assert-True ($readmeText -match 'more items failed or the elevated run was interrupted') `
    'README exit-code guidance does not explain the elevated interruption case.'
Assert-True ($batchText -match 'AEGIS-%RANDOM%-%RANDOM%') 'BAT does not use a unique temporary path.'

$releaseVersionMatch = [regex]::Match($installerText, '\$script:AegisVersion = ''(?<version>\d+\.\d+\.\d+)''')
Assert-True ($releaseVersionMatch.Success) 'Installer release version could not be identified.'
$releaseNotesPath = Join-Path $root ('.github\release-notes\v{0}.md' -f $releaseVersionMatch.Groups['version'].Value)
Assert-True (Test-Path -LiteralPath $releaseNotesPath) 'Release notes for the installer version are missing.'

Write-Host 'Checking pinned GitHub Actions...'
$releaseWorkflow = Get-Content -Raw (Join-Path $root '.github\workflows\release.yml')
Assert-True ($releaseWorkflow -match 'body_path: \.github/release-notes/\$\{\{ github\.ref_name \}\}\.md') `
    'Release workflow does not publish the notes for its tag.'
$workflowText = (Get-Content -Raw (Join-Path $root '.github\workflows\validate.yml')) + $releaseWorkflow
$actionLines = @($workflowText -split "`r?`n" | Where-Object { $_ -match '^\s+uses:' })
Assert-True ($actionLines.Count -eq 4) 'Unexpected GitHub Action count.'
foreach ($line in $actionLines) {
    Assert-True ($line -match '@[0-9a-f]{40}(\s+#.*)?$') "GitHub Action is not SHA-pinned: $line"
}

Write-Host 'Running non-destructive manifest listing...'
$listOutput = & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -ListPackages -NoColor 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "ListPackages failed: $listOutput"
foreach ($required in @(
    'M2Team.NanaZip',
    'Microsoft.PowerShell',
    'CreativeTechnology.OpenAL',
    'Amazon.Corretto.25.JDK',
    'Amazon.Corretto.21.JDK',
    'Amazon.Corretto.17.JDK',
    'Amazon.Corretto.8.JDK',
    'Windows.NetFx3',
    'Microsoft.DotNet.DesktopRuntime.9',
    'Microsoft.DotNet.DesktopRuntime.8.x86',
    'Microsoft.DotNet.AspNetCore.10'
    'Devolutions.UniGetUI'
    'voidtools.Everything.Beta'
    'VideoLAN.VLC.Nightly'
    '9N5JJZW4QZBR'
    'SublimeHQ.SublimeText.4'
    'Microsoft.VisualStudioCode.Insiders'
    'AntibodySoftware.WizTree'
)) {
    Assert-True ($listOutput -match [regex]::Escape($required)) "Manifest is missing $required."
}
foreach ($removed in @('Brave.Brave.Beta', 'Valve.Steam', 'Discord.Discord')) {
    Assert-True ($listOutput -notmatch [regex]::Escape($removed)) `
        "Unrelated optional software remains in the manifest: $removed"
}

Write-Host 'Checking irm | iex scope compatibility...'
$iexProbe = @'
$source = Get-Content -Raw -LiteralPath '__INSTALLER__'
$source = $source.Replace('[switch]$Help,', '[switch]$Help = $true,')
Invoke-Expression $source
Write-Output "IEX_RETURNED=$LASTEXITCODE"
'@.Replace('__INSTALLER__', $installer.Replace("'", "''"))
$iexOutput = & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -Command $iexProbe 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "Invoke-Expression compatibility failed: $iexOutput"
Assert-True ($iexOutput -match 'IEX_RETURNED=0') 'Invoke-Expression did not return to its caller.'
Assert-True ($iexOutput -notmatch 'attribute cannot be added') 'A parameter collided with caller scope.'

Write-Host 'Checking Install.ps1 has no byte-order mark...'
$installerBytes = [System.IO.File]::ReadAllBytes($installer)
$hasBom = $installerBytes.Length -ge 3 -and $installerBytes[0] -eq 0xEF -and
    $installerBytes[1] -eq 0xBB -and $installerBytes[2] -eq 0xBF
Assert-True (-not $hasBom) ('Install.ps1 has a UTF-8 BOM. Invoke-Expression (irm | iex) reads the ' +
    'raw fetched string, and a BOM there breaks [CmdletBinding()]/param() parsing -- this only ' +
    'shows up over the network, never via -File, so it will not fail here otherwise.')
Assert-True ($installerText -notmatch '[^\x00-\x7F]') `
    'Install.ps1 contains literal non-ASCII text; use runtime [char] codes so Windows PowerShell 5.1 can parse the BOM-less file.'

Write-Host 'Checking the documented one-liner survives a stray leading BOM...'
Assert-True ($readmeText -match [regex]::Escape('TrimStart([char]0xFEFF)')) `
    'README one-liner lost its BOM-stripping guard against irm/proxy/cache-injected BOMs.'
$bomProbe = @'
$source = Get-Content -Raw -LiteralPath '__INSTALLER__'
$source = $source.Replace('[switch]$Help,', '[switch]$Help = $true,')
$source = [char]0xFEFF + $source
$source = $source.TrimStart([char]0xFEFF)
Invoke-Expression $source
Write-Output "IEX_RETURNED=$LASTEXITCODE"
'@.Replace('__INSTALLER__', $installer.Replace("'", "''"))
$bomOutput = & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -Command $bomProbe 2>&1 | Out-String
Assert-True ($bomOutput -match 'IEX_RETURNED=0') `
    "The one-liner's BOM-stripping guard did not survive a simulated leading BOM: $bomOutput"

Write-Host 'Running non-destructive Recommended dry run...'
$run = Invoke-AegisDryRun -Arguments @('-Profile', 'Recommended')
$dryRunOutput = $run.Output
$dryRunLog = $run.Log
Assert-True ($run.ExitCode -eq 0) "Dry run failed: $dryRunOutput"
Assert-True ($dryRunOutput -match 'Dry run: no system changes') 'Dry-run notice is missing.'
Assert-True ($dryRunOutput -match 'INSTALLATION PLAN - 40 ITEMS') 'Recommended selection count changed.'
Assert-True ($dryRunOutput -match '40 ITEMS PLANNED') 'Preview summary is missing.'
Assert-True (@($dryRunOutput -split "`r?`n").Count -lt 80) 'Recommended dry run output is no longer compact.'
Assert-True ($dryRunLog -match 'NanaZip') 'NanaZip was not selected.'
Assert-True ($dryRunLog -match '\[Microsoft\.PowerShell\]') 'Current PowerShell was not selected.'
Assert-True ($dryRunLog -match 'ASP.NET Core Runtime 10') 'ASP.NET runtime was not selected.'
Assert-True ($dryRunLog -match 'Microsoft Visual C\+\+ 2005 Redistributable \(x86\)') `
    'x86 VC++ runtime was not selected on x64 Windows.'
Assert-True ($dryRunLog.IndexOf('Microsoft Visual C++ 2005 Redistributable (x86)') -lt `
    $dryRunLog.IndexOf('Microsoft Visual C++ 2005 Redistributable (x64)')) `
    'VC++ 2005 x86 must precede x64 to avoid WinGet package identity conflicts.'
Assert-True ($dryRunLog.IndexOf('Desktop Runtime 3.1') -lt $dryRunLog.IndexOf('Desktop Runtime 10')) `
    'Runtime versions are not sorted numerically.'
Assert-True ($dryRunLog -match 'Amazon Corretto 25 JDK') `
    'Recommended selection does not include the default Java runtime.'
Assert-True ($dryRunLog -notmatch 'Microsoft Visual C\+\+ v14 Redistributable \(Arm64\)') `
    'Architecture filtering selected Arm64 on an x64 test host.'
Assert-True ($dryRunLog -match 'Arguments: -DryRun -LogPath \S+ -NoColor -Profile Recommended -Unattended') `
    'The log does not record the supplied arguments.'

Write-Host 'Checking backwards-compatible Full alias...'
$run = Invoke-AegisDryRun -Arguments @('-Profile', 'Full')
Assert-True ($run.ExitCode -eq 0) "Full dry run failed: $($run.Output)"
Assert-True ($run.Output -match 'Profile Full is now an alias for Recommended') `
    'Full compatibility alias notice is missing.'
Assert-True ($run.Output -match 'INSTALLATION PLAN - 40 ITEMS') `
    'Full alias does not select the Recommended stack.'
Assert-True ($run.Log -match 'DirectPlay') 'Full profile is missing DirectPlay.'
Assert-True ($run.Log -match 'NVIDIA PhysX Legacy') 'Full profile is missing legacy PhysX.'

Write-Host 'Checking custom component selection...'
$run = Invoke-AegisDryRun -Arguments @('-Profile', 'Custom', '-IncludeGroup', 'VC++,DotNet,AspNet')
Assert-True ($run.ExitCode -eq 0) "Custom dry run failed: $($run.Output)"
Assert-True ($run.Output -match 'INSTALLATION PLAN - 30 ITEMS') `
    'Custom VC++/.NET/ASP.NET selection count changed.'
Assert-True ($run.Log -notmatch 'DirectX End-User Runtime') `
    'Custom runtime-only selection unexpectedly includes gaming extras.'

$run = Invoke-AegisDryRun -Arguments @('-Profile', 'Custom', '-IncludeGroup', 'Workbench')
Assert-True ($run.ExitCode -eq 0) "Workbench dry run failed: $($run.Output)"
Assert-True ($run.Output -match 'INSTALLATION PLAN - 7 ITEMS') `
    'Optional Workbench selection count changed.'
Assert-True ($run.Log -match 'Xtreme Download Manager') `
    'Microsoft Store XDM is missing from the Workbench.'
Assert-True ($run.Log -notmatch 'Amazon Corretto 25 JDK') `
    'Workbench unexpectedly pulls in the recommended prerequisite stack.'

Write-Host 'Checking selectable Corretto versions and legacy .NET feature...'
$run = Invoke-AegisDryRun -Arguments @('-Profile', 'Custom', '-IncludeGroup', 'Java')
Assert-True ($run.ExitCode -eq 0) "Java dry run failed: $($run.Output)"
Assert-True ($run.Output -match 'INSTALLATION PLAN - 4 ITEMS') `
    'Java component does not select the four Corretto JDK lines.'
Assert-True ($run.Log -match 'Amazon Corretto 21 JDK') 'Corretto 21 is not selectable.'
Assert-True ($run.Log -match 'Amazon Corretto 17 JDK') 'Corretto 17 is not selectable.'
Assert-True ($run.Log -match 'Amazon Corretto 8 JDK') 'Corretto 8 is not selectable.'

$run = Invoke-AegisDryRun -Arguments @('-Profile', 'Custom', '-IncludePackage', 'Amazon.Corretto.21.JDK')
Assert-True ($run.Output -match 'INSTALLATION PLAN - 1 ITEMS') 'A single Corretto version is not selectable.'

$run = Invoke-AegisDryRun -Arguments @('-Profile', 'Custom', '-IncludeGroup', 'Legacy')
Assert-True ($run.ExitCode -eq 0) "Legacy-feature dry run failed: $($run.Output)"
Assert-True ($run.Output -match 'INSTALLATION PLAN - 1 ITEMS') `
    '.NET Framework 3.5 should be an independently selectable item.'
Assert-True ($run.Log -match '\.NET Framework 3\.5') `
    '.NET Framework 3.5 is missing from the legacy component plan.'

Write-Host 'Checking the interactive menu fallback for redirected input...'
$menuOutput = "3`n`n" | & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -DryRun -NoColor 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "Menu fallback failed: $menuOutput"
Assert-True ($menuOutput -match 'INSTALLATION PLAN - 7 ITEMS') 'Workbench menu entry did not select the Workbench.'

$run = Invoke-AegisDryRun -Arguments @('-Profile', 'Custom', '-IncludeGroup', 'Nope')
Assert-True ($run.ExitCode -eq 1) 'Unknown component did not produce fatal exit code 1.'
Assert-True ($run.Output -match 'Valid components:') 'Unknown-component error does not list valid names.'

Write-Host 'Checking invalid package failure semantics...'
$invalidOutput = & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -Profile Custom -IncludePackage AEGIS.Does.Not.Exist `
    -DryRun -Unattended -NoColor 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 1) 'Unknown package did not produce fatal exit code 1.'
Assert-True ($invalidOutput -match 'Unknown package ID') 'Unknown-package error is not actionable.'

Write-Host 'All validation checks passed.' -ForegroundColor Green
exit 0
