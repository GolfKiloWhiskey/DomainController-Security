<#
.NOTES
    Author:  Cliff Waite
    Date:    11/21/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.1.0

.SYNOPSIS
    Tests for Get-NutmegAD.ps1 (download or update the toolkit on a server). No network needed.

.DESCRIPTION
    - Dot-sources the script with NUTMEG_GET_TEST set, so only its functions load.
    - Builds zips shaped like GitHub's (<owner>-<repo>-<commit>\...) and stands in for the download.
    - Covers the address, the version and commit read back, keeping the old copy, refusing a zip that
      is not the toolkit, the token only ever sent as a header, and plain reasons for GitHub's refusals.

.EXAMPLE
    pwsh -File .\Tests\Invoke-GetTests.ps1

.VERSIONING
    0.1.0 - Initial tests.
#>

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("NmGet_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -Path $work -ItemType Directory -Force | Out-Null

# The download, as GitHub would answer it.
$global:WebSeen = $null
$global:WebFail = $null
$global:ZipToServe = $null
function global:Invoke-WebRequest {
    param($Uri, $Headers, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
    $global:WebSeen = [pscustomobject]@{ Uri = $Uri; Auth = "$($Headers.Authorization)"; Progress = "$ProgressPreference" }
    if ($global:WebFail) { throw "Response status code does not indicate success: $global:WebFail" }
    Copy-Item -LiteralPath $global:ZipToServe -Destination $OutFile
}
# Unblock-File only works on Windows; stand in for it everywhere.
function global:Unblock-File { param([Parameter(ValueFromPipeline)]$InputObject) process { } }

function New-FakeZip {
    param([string]$Name, [string]$Version = '9.9.9', [switch]$NotToolkit)
    $src = Join-Path $work ("src_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $root = Join-Path $src "GolfKiloWhiskey-DomainController-Security-$Name"
    New-Item -Path (Join-Path $root 'Nutmeg.AD') -ItemType Directory -Force | Out-Null
    if (-not $NotToolkit) {
        Set-Content -Path (Join-Path $root 'Start-NutmegAD.ps1') -Value '# launcher'
        Set-Content -Path (Join-Path (Join-Path $root 'Nutmeg.AD') 'Nutmeg.AD.psd1') -Value "@{ ModuleVersion = '$Version' }"
    } else {
        Set-Content -Path (Join-Path $root 'README.md') -Value 'something else'
    }
    $zip = "$src.zip"
    Compress-Archive -Path $root -DestinationPath $zip -Force
    return $zip
}

$env:NUTMEG_GET_TEST = '1'
. (Join-Path $repoRoot 'Get-NutmegAD.ps1')
Remove-Item Env:\NUTMEG_GET_TEST

$script:Passed = 0
$script:Failed = New-Object System.Collections.Generic.List[string]
function Test-That {
    param([string]$Name, [scriptblock]$Body)
    try {
        $result = & $Body
        if ($result -eq $false) { throw 'returned false' }
        $script:Passed++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } catch {
        $script:Failed.Add("$Name - $($_.Exception.Message)")
        Write-Host "  [FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host '   Get-NutmegAD.ps1 tests' -ForegroundColor Yellow
Write-Host '=============================================' -ForegroundColor Cyan

Test-That 'The address is the branch zip, and a branch with a slash keeps it' {
    (Get-NutmegZipUri -Repository 'GolfKiloWhiskey/DomainController-Security' -Branch 'main') -eq 'https://api.github.com/repos/GolfKiloWhiskey/DomainController-Security/zipball/main' -and
        (Get-NutmegZipUri -Repository 'GolfKiloWhiskey/DomainController-Security' -Branch 'claude/zen-franklin-4swcvy') -eq 'https://api.github.com/repos/GolfKiloWhiskey/DomainController-Security/zipball/claude/zen-franklin-4swcvy'
}

Test-That 'A first install puts the toolkit in the folder and reports its version and commit' {
    $target = Join-Path $work 'first\DomainController-Security'
    $r = Install-NutmegPackage -ZipPath (New-FakeZip -Name 'abc1234' -Version '0.2.0') -Path $target
    $r.Version -eq '0.2.0' -and $r.Commit -eq 'abc1234' -and (Test-Path (Join-Path $target 'Start-NutmegAD.ps1')) -and -not $r.Previous
}

Test-That 'An update keeps the old copy as .previous, replacing the one before' {
    $target = Join-Path $work 'update\DomainController-Security'
    $null = Install-NutmegPackage -ZipPath (New-FakeZip -Name '1111111' -Version '0.1.0') -Path $target
    $null = Install-NutmegPackage -ZipPath (New-FakeZip -Name '2222222' -Version '0.2.0') -Path $target
    $r = Install-NutmegPackage -ZipPath (New-FakeZip -Name '3333333' -Version '0.3.0') -Path $target
    $prevVersion = "$((Import-PowerShellDataFile -Path (Join-Path (Join-Path "$target.previous" 'Nutmeg.AD') 'Nutmeg.AD.psd1')).ModuleVersion)"
    $r.Version -eq '0.3.0' -and $r.Previous -eq "$target.previous" -and $prevVersion -eq '0.2.0'
}

Test-That 'A zip that is not the toolkit is refused, and the copy already there is untouched' {
    $target = Join-Path $work 'refuse\DomainController-Security'
    $null = Install-NutmegPackage -ZipPath (New-FakeZip -Name '4444444' -Version '0.2.0') -Path $target
    $refused = $false
    try { $null = Install-NutmegPackage -ZipPath (New-FakeZip -Name '5555555' -NotToolkit) -Path $target } catch { $refused = $_.Exception.Message -match 'does not look like' }
    $still = "$((Import-PowerShellDataFile -Path (Join-Path (Join-Path $target 'Nutmeg.AD') 'Nutmeg.AD.psd1')).ModuleVersion)"
    $refused -and $still -eq '0.2.0' -and -not (Test-Path "$target.previous")
}

Test-That 'The token goes only into the request header, never into the files' {
    $global:WebFail = $null
    $global:ZipToServe = New-FakeZip -Name '6666666'
    $secure = ConvertTo-SecureString -String 'not-a-real-token-123' -AsPlainText -Force
    $out = Join-Path $work 'dl.zip'
    Get-NutmegPackage -Uri 'https://api.github.com/repos/x/y/zipball/main' -OutFile $out -Token $secure
    $target = Join-Path $work 'token\DomainController-Security'
    $null = Install-NutmegPackage -ZipPath $out -Path $target
    $leak = @(Get-ChildItem -Path $work -Recurse -File | Select-String -SimpleMatch 'not-a-real-token-123')
    $global:WebSeen.Auth -eq 'Bearer not-a-real-token-123' -and $leak.Count -eq 0
}

Test-That 'The download runs with the progress bar off (5.1 crawls with it on)' {
    $global:WebFail = $null
    $global:ZipToServe = New-FakeZip -Name '8888888'
    Get-NutmegPackage -Uri 'https://api.github.com/repos/x/y/zipball/main' -OutFile (Join-Path $work 'speed.zip')
    $global:WebSeen.Progress -eq 'SilentlyContinue'
}

Test-That 'Without a token (-Public) no Authorization header is sent' {
    $global:WebFail = $null
    $global:ZipToServe = New-FakeZip -Name '7777777'
    Get-NutmegPackage -Uri 'https://api.github.com/repos/x/y/zipball/main' -OutFile (Join-Path $work 'pub.zip')
    $global:WebSeen.Auth -eq ''
}

Test-That 'GitHub refusals come back in plain words' {
    $secure = ConvertTo-SecureString -String 'x' -AsPlainText -Force
    $msgs = foreach ($code in '401', '403', '404') {
        $global:WebFail = $code
        try { Get-NutmegPackage -Uri 'https://api.github.com/repos/x/y/zipball/nope' -OutFile (Join-Path $work "f$code.zip") -Token $secure; 'no error' } catch { $_.Exception.Message }
    }
    $global:WebFail = $null
    $msgs[0] -match 'refused the token' -and $msgs[1] -match 'Contents: Read-only' -and $msgs[2] -match 'does not exist'
}

Test-That 'After the download: the build (workgroup) or the toolkit (domain member), both in the window unless -Console; nothing with -NoStart' {
    (Get-NutmegStartChoice -PartOfDomain $false) -eq 'NewForestWindow' -and (Get-NutmegStartChoice -PartOfDomain $false -Console) -eq 'NewForest' -and
        (Get-NutmegStartChoice -PartOfDomain $true) -eq 'Window' -and (Get-NutmegStartChoice -PartOfDomain $true -Console) -eq 'Menu' -and
        (Get-NutmegStartChoice -PartOfDomain $false -NoStart) -eq 'None' -and (Get-NutmegStartChoice -PartOfDomain $true -StartBuild) -eq 'NewForestWindow' -and
        (Get-NutmegStartChoice -PartOfDomain $true -StartBuild -Console) -eq 'NewForest' -and (Get-NutmegStartChoice -PartOfDomain $false -Start) -eq 'Window'
}

Test-That 'PowerShell 7: checked after the download and before the start; skipped off Windows or with -SkipPowerShell7, installed without asking' {
    $text = Get-Content -LiteralPath (Join-Path $repoRoot 'Get-NutmegAD.ps1') -Raw
    $check = $text.IndexOf("`$ps7 = Install-NutmegPowerShell7"); $start = $text.IndexOf("`$choice = Get-NutmegStartChoice")
    $wasOs = $env:OS
    try {
        $env:OS = 'Windows_NT'
        $skip = Install-NutmegPowerShell7 -Path $work -Skip
        $env:OS = 'Linux'
        $notWin = Install-NutmegPowerShell7 -Path $work
    } finally { $env:OS = $wasOs }
    ($check -gt 0) -and ($check -lt $start) -and ($skip -eq 'Skipped (-SkipPowerShell7)') -and ($notWin -eq 'Skipped (not Windows)') -and
        $text.Contains("Install-NmPowerShell7 -ApprovedBy 'Get-NutmegAD.ps1: PowerShell 7 is part of every toolkit server'")
}

Test-That 'The script clears the screen before its header (issue #6)' {
    $text = Get-Content -LiteralPath (Join-Path $repoRoot 'Get-NutmegAD.ps1') -Raw
    $clear = $text.IndexOf("`nClear-Host")
    $clear -gt 0 -and $clear -lt $text.IndexOf("Nutmeg AD Toolkit: get or update'")
}

Test-That 'The script starts the log in the toolkit''s format and hands it to the launcher' {
    $log = Start-NutmegLog -Folder (Join-Path $work 'Logs')
    Write-Step 'Downloading...'
    Write-Step 'Something failed' Red
    $lines = @(Get-Content -LiteralPath $log)
    $script:GetLogPath = $null
    (Split-Path -Leaf $log) -like 'NutmegAD_*.txt' -and $lines[0] -match '^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] \[INFO\] Downloading\.\.\.$' -and
        $lines[1] -match '\[ERROR\] Something failed$'
}

Test-That 'The launcher really receives -NewForest and -LogPath as given (a probe with its parameters)' {
    # A stand-in with the launcher's own param block, called the way Get-NutmegAD.ps1 calls it.
    $probe = Join-Path $work 'Probe.ps1'
    $launcherText = Get-Content -LiteralPath (Join-Path $repoRoot 'Start-NutmegAD.ps1') -Raw
    $paramLine = ([regex]::Match($launcherText, '(?m)^param\(.*\)$')).Value
    Set-Content -Path $probe -Value ($paramLine + "`n" + '[pscustomobject]@{ NewForest = [bool]$NewForest; Gui = [bool]$Gui; LogPath = $LogPath }')
    $log = 'C:\Temp\NutmegAD\Logs\NutmegAD_20261121-0119-47.txt'
    $nfArgs = Get-NutmegLauncherArgs -Choice NewForest -LogPath $log
    $menuArgs = Get-NutmegLauncherArgs -Choice Menu -LogPath $log
    $nf = & $probe @nfArgs
    $menu = & $probe @menuArgs
    $winArgs = Get-NutmegLauncherArgs -Choice Window -LogPath $log
    $win = & $probe @winArgs
    $nfwArgs = Get-NutmegLauncherArgs -Choice NewForestWindow -LogPath $log
    $nfw = & $probe @nfwArgs
    $paramLine -match 'LogPath' -and $nf.NewForest -and (-not $nf.Gui) -and $nf.LogPath -eq $log -and (-not $menu.NewForest) -and (-not $menu.Gui) -and $menu.LogPath -eq $log -and
        $win.Gui -and (-not $win.NewForest) -and $win.LogPath -eq $log -and $nfw.Gui -and $nfw.NewForest -and $nfw.LogPath -eq $log
}

Test-That 'The launcher ignores a -LogPath that is really a parameter name' {
    $text = Get-Content -LiteralPath (Join-Path $repoRoot 'Start-NutmegAD.ps1') -Raw
    $text -match "if \(\`$LogPath -and \`$LogPath\.StartsWith\('-'\)\) \{ \`$LogPath = '' \}"
}

Test-That 'Run from elsewhere, the script updates itself from the download; the same copy is left alone' {
    $target = Join-Path $work 'self\DomainController-Security'
    $null = Install-NutmegPackage -ZipPath (New-FakeZip -Name '9999999') -Path $target
    Set-Content -Path (Join-Path $target 'Get-NutmegAD.ps1') -Value "`$ScriptVersion = '9.9'"
    $old = Join-Path $work 'self-old.ps1'
    Set-Content -Path $old -Value "`$ScriptVersion = '1.4'"
    $v1 = Update-NutmegSelf -Self $old -Path $target
    $v2 = Update-NutmegSelf -Self $old -Path $target                        # already the same
    $v3 = Update-NutmegSelf -Self (Join-Path $target 'Get-NutmegAD.ps1') -Path $target   # run from the toolkit folder
    $v1 -eq '9.9' -and (Get-Content $old -Raw) -match "'9.9'" -and $v2 -eq '' -and $v3 -eq ''
}

Test-That 'Updating while standing in the toolkit folder steps out of it first' {
    $target = Join-Path $work 'cwd\DomainController-Security'
    $null = Install-NutmegPackage -ZipPath (New-FakeZip -Name 'aaaaaaa') -Path $target
    $was = Get-Location
    try {
        Set-Location -LiteralPath $target
        $r = Install-NutmegPackage -ZipPath (New-FakeZip -Name 'bbbbbbb') -Path $target
        $now = (Get-Location).ProviderPath
    } finally { Set-Location $was }
    $r.Commit -eq 'bbbbbbb' -and $now -eq (Split-Path -Parent $target)
}

Test-That 'The script is ASCII only and never uses -ExecutionPolicy Bypass or saves the token' {
    $text = Get-Content -LiteralPath (Join-Path $repoRoot 'Get-NutmegAD.ps1') -Raw
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $repoRoot 'Get-NutmegAD.ps1'))
    (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) -and ($text -notmatch 'Bypass') -and ($text -notmatch 'Set-Content[^\r\n]*token') -and ($text -notmatch 'Export-Clixml')
}

Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '=============================================' -ForegroundColor Cyan
if ($script:Failed.Count -eq 0) {
    Write-Host "   All $script:Passed tests passed." -ForegroundColor Green
    Write-Host '=============================================' -ForegroundColor Cyan
    exit 0
}
Write-Host "   $($script:Failed.Count) failed, $script:Passed passed:" -ForegroundColor Red
$script:Failed | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
Write-Host '=============================================' -ForegroundColor Cyan
exit 1
