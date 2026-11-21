<#
.NOTES
    Author:  Cliff Waite
    Date:    11/21/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 1.0

.SYNOPSIS
    Downloads (or updates) the Nutmeg AD Toolkit onto this server from GitHub.

.DESCRIPTION
    - Standalone: not part of the Nutmeg.AD module. Copy this one file to a server (or paste it into
      Windows PowerShell) to put the toolkit there.
    - Asks for a GitHub token without showing it (fine-grained, this repository only, Contents:
      Read-only). The token is used for the one download and never written to disk, the log or the
      PowerShell history. -Public skips it if the repository is ever made public.
    - Downloads the chosen branch (main by default) as a zip, checks it is the toolkit, and puts it in
      C:\Tools\DomainController-Security (or -Path). An existing copy is kept next to it as
      <folder>.previous, replacing the one before.
    - Unblocks the files, so Windows runs them and the New Forest Build's pre-flight passes.
    - Shows the toolkit version and the commit it came from. -StartBuild then opens the New Forest
      Build; -Start opens the main menu.
    - Runs in Windows PowerShell 5.1 and PowerShell 7. Run it as administrator when the folder is
      under C:\Tools or another protected place.

.EXAMPLE
    .\Get-NutmegAD.ps1
    Asks for the token and puts the main branch in C:\Tools\DomainController-Security.

.EXAMPLE
    .\Get-NutmegAD.ps1 -Branch claude/zen-franklin-4swcvy -StartBuild
    Gets a branch that is still in review and starts the New Forest Build.

.EXAMPLE
    .\Get-NutmegAD.ps1 -Path D:\Tools\NutmegAD
    Puts the toolkit somewhere else.

.VERSIONING
    1.0 - First version: token prompt, branch, download, check, backup of the old copy, unblock, start.
#>
[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [string]$Path = 'C:\Tools\DomainController-Security',
    [string]$Repository = 'GolfKiloWhiskey/DomainController-Security',
    [switch]$Public,
    [switch]$StartBuild,
    [switch]$Start
)

$ScriptVersion = '1.0'
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Text, [string]$Color = 'Cyan')
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Text" -ForegroundColor $Color
}

function Get-NutmegZipUri {
    # The GitHub API address of a branch's zip.
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Branch)
    return "https://api.github.com/repos/$Repository/zipball/$([uri]::EscapeDataString($Branch).Replace('%2F', '/'))"
}

function ConvertFrom-NutmegSecure {
    # The plain text of a SecureString, for the one request that needs it.
    param([Parameter(Mandatory)][securestring]$Secure)
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Get-NutmegPackage {
    <#
    .SYNOPSIS
        Downloads the branch zip to a file. Throws a plain reason on 401, 403 or 404.
    #>
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$OutFile, [securestring]$Token)
    $headers = @{ 'User-Agent' = 'NutmegAD-Get'; Accept = 'application/vnd.github+json' }
    $plain = $null
    if ($Token) { $plain = ConvertFrom-NutmegSecure -Secure $Token; $headers.Authorization = "Bearer $plain" }
    try {
        Invoke-WebRequest -Uri $Uri -Headers $headers -OutFile $OutFile -UseBasicParsing -TimeoutSec 300
    } catch {
        $m = "$($_.Exception.Message)"
        if ($m -match '401') { throw 'GitHub refused the token (401). Check it is current and copied whole.' }
        if ($m -match '403') { throw 'GitHub refused the request (403). The token needs Contents: Read-only on this repository.' }
        if ($m -match '404') { throw "Not found (404): the branch '$Branch' does not exist, or the token cannot see $Repository." }
        throw "Download failed: $m"
    } finally {
        $plain = $null
        $headers.Remove('Authorization')
    }
}

function Install-NutmegPackage {
    <#
    .SYNOPSIS
        Unpacks the zip, checks it is the toolkit, keeps the old copy as <Path>.previous and moves the
        new one into place. Returns the toolkit version and the commit.
    #>
    param([Parameter(Mandatory)][string]$ZipPath, [Parameter(Mandatory)][string]$Path)
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("NutmegAD_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $work -Force
        $root = @(Get-ChildItem -Path $work -Directory)[0]
        if (-not $root) { throw 'The download was empty.' }
        $manifest = Join-Path (Join-Path $root.FullName 'Nutmeg.AD') 'Nutmeg.AD.psd1'
        if (-not (Test-Path -LiteralPath (Join-Path $root.FullName 'Start-NutmegAD.ps1')) -or -not (Test-Path -LiteralPath $manifest)) {
            throw 'The download does not look like the Nutmeg AD Toolkit (no Start-NutmegAD.ps1 or Nutmeg.AD.psd1). Nothing was changed.'
        }
        $version = "$((Import-PowerShellDataFile -Path $manifest).ModuleVersion)"
        # GitHub names the folder <owner>-<repo>-<commit>.
        $commit = if ($root.Name -match '-([0-9a-f]{7,40})$') { $Matches[1] } else { 'unknown' }

        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
        $previous = "$Path.previous"
        if (Test-Path -LiteralPath $Path) {
            if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Recurse -Force }
            Move-Item -LiteralPath $Path -Destination $previous
        }
        Move-Item -LiteralPath $root.FullName -Destination $Path
        Get-ChildItem -LiteralPath $Path -Recurse -File | Unblock-File
        return [pscustomobject]@{ Version = $version; Commit = $commit; Path = $Path; Previous = $(if (Test-Path -LiteralPath $previous) { $previous } else { '' }) }
    } finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# Tests dot-source this file with NUTMEG_GET_TEST set, to reach the functions without running it.
if ($env:NUTMEG_GET_TEST) { return }

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host '   Nutmeg AD Toolkit: get or update' -ForegroundColor Yellow
Write-Host '   Author: Cliff Waite' -ForegroundColor DarkGray
Write-Host '   Email: cliff.ps@nutmegtech.com' -ForegroundColor DarkGray
Write-Host "   Version: $ScriptVersion" -ForegroundColor DarkGray
Write-Host '=============================================' -ForegroundColor Cyan
Write-Step "Repository $Repository, branch $Branch, into $Path"

if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

$token = $null
if (-not $Public) {
    Write-Host 'GitHub token (fine-grained, this repository, Contents: Read-only). It is not shown, saved or logged.' -ForegroundColor Yellow
    $token = Read-Host -Prompt 'Token' -AsSecureString
    if ($token.Length -eq 0) { Write-Step 'No token typed; nothing was changed.' Red; return }
}

$zip = Join-Path ([System.IO.Path]::GetTempPath()) ("NutmegAD_" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.zip')
try {
    Write-Step 'Downloading...'
    Get-NutmegPackage -Uri (Get-NutmegZipUri -Repository $Repository -Branch $Branch) -OutFile $zip -Token $token
    $token = $null
    Write-Step 'Unpacking and checking...'
    $r = Install-NutmegPackage -ZipPath $zip -Path $Path
    Write-Step "Nutmeg AD Toolkit $($r.Version) (commit $($r.Commit)) is in $($r.Path)." Green
    if ($r.Previous) { Write-Step "The copy that was there is kept in $($r.Previous)." DarkGray }
} catch {
    Write-Step "$($_.Exception.Message)" Red
    return
} finally {
    $token = $null
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
}

$launcher = Join-Path $Path 'Start-NutmegAD.ps1'
if ($StartBuild) {
    & $launcher -NewForest
} elseif ($Start) {
    & $launcher
} else {
    Write-Step "Next: cd '$Path'; .\Start-NutmegAD.ps1 -NewForest   (a new forest)   or   .\Start-NutmegAD.ps1   (the menu)" DarkGray
}
