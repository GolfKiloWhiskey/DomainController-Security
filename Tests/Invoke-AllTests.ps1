<#
.NOTES
    Author:  Cliff Waite
    Date:    11/17/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 1.0

.SYNOPSIS
    Runs every Tests/Invoke-*Tests.ps1 file, each in its own PowerShell process, and prints a total.

.DESCRIPTION
    - Each test file runs in a fresh process (they define global fake cmdlets that would clash).
    - Prints one line per file and the total; exits with code 1 if any file fails.
    - Uses the same PowerShell that runs this script (pwsh or powershell.exe).

.EXAMPLE
    pwsh -File .\Tests\Invoke-AllTests.ps1

.VERSIONING
    1.0 - First version.
#>

$ErrorActionPreference = 'Stop'
$exe = (Get-Process -Id $PID).Path
$files = @(Get-ChildItem -Path $PSScriptRoot -Filter 'Invoke-*Tests.ps1' | Where-Object { $_.Name -ne 'Invoke-AllTests.ps1' } | Sort-Object Name)
$total = 0
$failed = New-Object System.Collections.Generic.List[string]

foreach ($f in $files) {
    $out = & $exe -NoProfile -File $f.FullName 2>&1 | Out-String
    $ok = $LASTEXITCODE -eq 0
    $n = if ($out -match 'All (\d+) tests passed') { [int]$Matches[1] } elseif ($out -match '(\d+) failed, (\d+) passed') { [int]$Matches[2] } else { 0 }
    $total += $n
    if ($ok) {
        Write-Host ('  [PASS] {0,-40} {1,4} tests' -f $f.Name, $n) -ForegroundColor Green
    } else {
        $failed.Add($f.Name)
        Write-Host ('  [FAIL] {0}' -f $f.Name) -ForegroundColor Red
        ($out -split "`r?`n") | Where-Object { $_ -match '\[FAIL\]|^\s+- ' } | ForEach-Object { Write-Host "         $_" -ForegroundColor Red }
    }
}

Write-Host '=============================================' -ForegroundColor Cyan
if ($failed.Count -eq 0) {
    Write-Host "   All $total tests passed in $($files.Count) files." -ForegroundColor Green
    exit 0
}
Write-Host "   $($failed.Count) file(s) failed: $($failed -join ', ') ($total tests passed)" -ForegroundColor Red
exit 1
