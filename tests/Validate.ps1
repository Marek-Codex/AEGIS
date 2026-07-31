$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'Install.ps1'
$batch = Join-Path $root 'Install.bat'
$readme = Join-Path $root 'README.md'

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
Assert-True ($installerText -match 'Start-Process.+-Verb RunAs') 'DirectPlay elevation helper is missing.'
Assert-True ($installerText -match '\$PID') 'Default log path is not process-unique.'
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
$listOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -ListPackages -NoColor 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "ListPackages failed: $listOutput"
foreach ($required in @(
    'M2Team.NanaZip',
    'CreativeTechnology.OpenAL',
    'Devolutions.UniGetUI',
    'Amazon.Corretto.25.JDK',
    'Brave.Brave.Beta'
)) {
    Assert-True ($listOutput -match [regex]::Escape($required)) "Manifest is missing $required."
}

Write-Host 'Checking irm | iex scope compatibility...'
$iexProbe = @'
$source = Get-Content -Raw -LiteralPath '__INSTALLER__'
$source = $source.Replace('[switch]$Help,', '[switch]$Help = $true,')
Invoke-Expression $source
Write-Output "IEX_RETURNED=$LASTEXITCODE"
'@.Replace('__INSTALLER__', $installer.Replace("'", "''"))
$iexOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -Command $iexProbe 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "Invoke-Expression compatibility failed: $iexOutput"
Assert-True ($iexOutput -match 'IEX_RETURNED=0') 'Invoke-Expression did not return to its caller.'
Assert-True ($iexOutput -notmatch 'attribute cannot be added') 'A parameter collided with caller scope.'

Write-Host 'Running non-destructive Modern dry run...'
$dryRunOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -Profile Modern -IncludeGroup Utilities -DryRun -Unattended -NoColor 2>&1 |
    Out-String
Assert-True ($LASTEXITCODE -eq 0) "Dry run failed: $dryRunOutput"
Assert-True ($dryRunOutput -match 'Dry run: no system changes') 'Dry-run notice is missing.'
Assert-True ($dryRunOutput -match 'NanaZip') 'Utilities group was not selected.'
Assert-True ($dryRunOutput -match 'OpenAL') 'Modern runtime was not selected.'
Assert-True ($dryRunOutput -match 'INSTALLATION PLAN - 9 ITEMS') 'Modern + Utilities selection count changed.'
Assert-True ($dryRunOutput -notmatch 'Microsoft Visual C\+\+ v14 Redistributable \(Arm64\)') `
    'Architecture filtering selected Arm64 on an x64 test host.'

Write-Host 'Checking Full profile composition...'
$fullOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -Profile Full -DryRun -Unattended -NoColor 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 0) "Full dry run failed: $fullOutput"
Assert-True ($fullOutput -match 'INSTALLATION PLAN - 27 ITEMS') 'Full runtime selection count changed.'
Assert-True ($fullOutput -match 'DirectPlay') 'Full profile is missing DirectPlay.'
Assert-True ($fullOutput -match 'NVIDIA PhysX Legacy') 'Full profile is missing legacy PhysX.'
Assert-True ($fullOutput -notmatch 'Brave Beta') 'Full runtime profile unexpectedly includes optional apps.'

Write-Host 'Checking invalid package failure semantics...'
$invalidOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $installer -Profile Custom -IncludePackage AEGIS.Does.Not.Exist `
    -DryRun -Unattended -NoColor 2>&1 | Out-String
Assert-True ($LASTEXITCODE -eq 1) 'Unknown package did not produce fatal exit code 1.'
Assert-True ($invalidOutput -match 'Unknown package ID') 'Unknown-package error is not actionable.'

Write-Host 'All validation checks passed.' -ForegroundColor Green
exit 0
