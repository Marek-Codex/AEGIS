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
Assert-True ($installerText -match 'PACKAGE \{0:D2\} / \{1:D2\}') `
    'Per-stage package progress is missing.'
Assert-True ($installerText -match 'RESTART RECOMMENDED') `
    'Prominent restart guidance is missing.'
Assert-True ($installerText -match 'Administrator request cancelled') `
    'UAC cancellation is not handled cleanly.'
Assert-True ($batchText -match 'AEGIS-%RANDOM%-%RANDOM%') 'BAT does not use a unique temporary path.'

Write-Host 'Checking pinned GitHub Actions...'
$workflowText = (Get-Content -Raw (Join-Path $root '.github\workflows\validate.yml')) +
    (Get-Content -Raw (Join-Path $root '.github\workflows\release.yml'))
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
$dryRunOutput = & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -Profile Recommended -DryRun -Unattended -NoColor 2>&1 |
    Out-String
Assert-True ($LASTEXITCODE -eq 0) "Dry run failed: $dryRunOutput"
Assert-True ($dryRunOutput -match 'Dry run: no system changes') 'Dry-run notice is missing.'
Assert-True ($dryRunOutput -match 'NanaZip') 'NanaZip was not selected.'
Assert-True ($dryRunOutput -match 'PowerShell') 'Current PowerShell was not selected.'
Assert-True ($dryRunOutput -match 'ASP.NET Core Runtime 10') 'ASP.NET runtime was not selected.'
Assert-True ($dryRunOutput -match 'Microsoft Visual C\+\+ 2005 Redistributable \(x86\)') `
    'x86 VC++ runtime was not selected on x64 Windows.'
Assert-True ($dryRunOutput.IndexOf('Microsoft Visual C++ 2005 Redistributable (x86)') -lt `
    $dryRunOutput.IndexOf('Microsoft Visual C++ 2005 Redistributable (x64)')) `
    'VC++ 2005 x86 must precede x64 to avoid WinGet package identity conflicts.'
Assert-True ($dryRunOutput -match 'Amazon Corretto 25 JDK') `
    'Recommended selection does not include the default Java runtime.'
Assert-True ($dryRunOutput -match 'INSTALLATION PLAN - 40 ITEMS') `
    'Recommended selection count changed.'
Assert-True ($dryRunOutput -notmatch 'Microsoft Visual C\+\+ v14 Redistributable \(Arm64\)') `
    'Architecture filtering selected Arm64 on an x64 test host.'

Write-Host 'Checking backwards-compatible Full alias...'
$fullOutput = & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -Profile Full -DryRun -Unattended -NoColor 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "Full dry run failed: $fullOutput"
Assert-True ($fullOutput -match 'Profile Full is now an alias for Recommended') `
    'Full compatibility alias notice is missing.'
Assert-True ($fullOutput -match 'INSTALLATION PLAN - 40 ITEMS') `
    'Full alias does not select the Recommended stack.'
Assert-True ($fullOutput -match 'DirectPlay') 'Full profile is missing DirectPlay.'
Assert-True ($fullOutput -match 'NVIDIA PhysX Legacy') 'Full profile is missing legacy PhysX.'

Write-Host 'Checking custom component selection...'
$customOutput = & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -Profile Custom -IncludeGroup VC++,DotNet,AspNet `
    -DryRun -Unattended -NoColor 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "Custom dry run failed: $customOutput"
Assert-True ($customOutput -match 'INSTALLATION PLAN - 30 ITEMS') `
    'Custom VC++/.NET/ASP.NET selection count changed.'
Assert-True ($customOutput -notmatch 'DirectX End-User Runtime') `
    'Custom runtime-only selection unexpectedly includes gaming extras.'

$workbenchOutput = & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -Profile Custom -IncludeGroup Workbench `
    -DryRun -Unattended -NoColor 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "Workbench dry run failed: $workbenchOutput"
Assert-True ($workbenchOutput -match 'INSTALLATION PLAN - 7 ITEMS') `
    'Optional Workbench selection count changed.'
Assert-True ($workbenchOutput -match 'Xtreme Download Manager') `
    'Microsoft Store XDM is missing from the Workbench.'
Assert-True ($workbenchOutput -notmatch 'Amazon Corretto 25 JDK') `
    'Workbench unexpectedly pulls in the recommended prerequisite stack.'

Write-Host 'Checking invalid package failure semantics...'
$invalidOutput = & $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -Profile Custom -IncludePackage AEGIS.Does.Not.Exist `
    -DryRun -Unattended -NoColor 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 1) 'Unknown package did not produce fatal exit code 1.'
Assert-True ($invalidOutput -match 'Unknown package ID') 'Unknown-package error is not actionable.'

Write-Host 'All validation checks passed.' -ForegroundColor Green
exit 0
