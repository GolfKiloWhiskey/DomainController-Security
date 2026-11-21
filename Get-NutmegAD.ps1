<#
.NOTES
    Author:  Cliff Waite
    Date:    11/21/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 1.7

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
    - Writes what it does to a log in C:\Temp\NutmegAD\Logs (never the token) and hands that log to
      the toolkit, which carries on in it (through every restart of a New Forest Build).
    - Run from outside the toolkit folder (C:\Temp, say), it replaces itself with the copy just
      downloaded, so the next run uses the latest version.
    - Shows the toolkit version and the commit it came from, then changes to the toolkit folder and
      starts it: the New Forest Build on a workgroup server (console only), the window on a
      domain-joined server or DC. -Console starts the console menu instead, -StartBuild the build,
      -Start the window; -NoStart only downloads.
    - Runs in Windows PowerShell 5.1 and PowerShell 7. Run it as administrator when the folder is
      under C:\Tools or another protected place.

.EXAMPLE
    .\Get-NutmegAD.ps1
    Asks for the token, puts the main branch in C:\Tools\DomainController-Security and starts it
    (the New Forest Build on a fresh workgroup server).

.EXAMPLE
    .\Get-NutmegAD.ps1 -Branch claude/zen-franklin-4swcvy -StartBuild
    Gets a branch that is still in review and starts the New Forest Build.

.EXAMPLE
    .\Get-NutmegAD.ps1 -Console
    Updates, then opens the console menu instead of the window.

.EXAMPLE
    .\Get-NutmegAD.ps1 -NoStart
    Only downloads or updates; starts nothing.

.EXAMPLE
    .\Get-NutmegAD.ps1 -Path D:\Tools\NutmegAD
    Puts the toolkit somewhere else.

.VERSIONING
    1.7 - Opens the window on a domain-joined server or DC (-Console for the menu); the build stays in the console.
    1.6 - Updates itself from the download when run from elsewhere; steps out of the toolkit folder before replacing it.
    1.5 - Hands -NewForest and -LogPath to the launcher as named parameters (a list bound them in order: the log path became '-LogPath').
    1.4 - Starts the log (C:\Temp\NutmegAD\Logs) and hands it to the toolkit, so a build has one log throughout.
    1.3 - Clears the screen when it starts (issue #6).
    1.2 - Changes to the toolkit folder and starts it: the build on a workgroup server, the menu otherwise; -NoStart.
    1.1 - Downloads with the progress bar off (Windows PowerShell 5.1 was slowed to a few hundred KB/s by it).
    1.0 - First version: token prompt, branch, download, check, backup of the old copy, unblock, start.
#>
[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [string]$Path = 'C:\Tools\DomainController-Security',
    [string]$Repository = 'GolfKiloWhiskey/DomainController-Security',
    [switch]$Public,
    [switch]$StartBuild,
    [switch]$Start,
    [switch]$Console,
    [switch]$NoStart,
    [string]$LogFolder = $(if ($env:OS -eq 'Windows_NT') { 'C:\Temp\NutmegAD\Logs' } else { Join-Path ([System.IO.Path]::GetTempPath()) 'NutmegAD/Logs' })
)

$ScriptVersion = '1.7'
$ErrorActionPreference = 'Stop'

$script:GetLogPath = $null

function Start-NutmegLog {
    # Starts the log the toolkit carries on in (NutmegAD_<time>.txt, the toolkit's own format).
    param([Parameter(Mandatory)][string]$Folder)
    if (-not (Test-Path -LiteralPath $Folder)) { New-Item -Path $Folder -ItemType Directory -Force | Out-Null }
    $script:GetLogPath = Join-Path $Folder "NutmegAD_$(Get-Date -Format 'yyyyMMdd-HHmm-ss').txt"
    return $script:GetLogPath
}

function Write-Step {
    # On screen, and in the log once it is started. Never given the token.
    param([string]$Text, [string]$Color = 'Cyan')
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Text" -ForegroundColor $Color
    if ($script:GetLogPath) {
        $level = switch ($Color) { 'Red' { 'ERROR' } 'Green' { 'SUCCESS' } 'DarkGray' { 'DETAIL' } default { 'INFO' } }
        try { Add-Content -Path $script:GetLogPath -Value ('[{0}] [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $level, $Text) -Encoding UTF8 -ErrorAction Stop } catch { $null = $_ }
    }
}

function Get-NutmegLauncherArgs {
    # The launcher's parameters for a start choice, carrying the log on. A hashtable: splatting a list
    # into a script binds the words in order, so '-LogPath' would become the log's path (and
    # '-NewForest' would be lost), which is what broke the hand-off to PowerShell 7.
    param([Parameter(Mandatory)][string]$Choice, [string]$LogPath)
    $a = @{}
    if ($Choice -eq 'NewForest') { $a.NewForest = $true }
    if ($Choice -eq 'Window') { $a.Gui = $true }
    if ($LogPath) { $a.LogPath = $LogPath }
    return $a
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
    # Windows PowerShell 5.1's progress bar slows downloads to a crawl; with it off they run at full speed.
    $ProgressPreference = 'SilentlyContinue'
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
            # Windows will not rename a folder the console is standing in: step out of it first.
            $here = (Get-Location).ProviderPath
            if ($here -and ($here.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar).StartsWith($Path.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                Set-Location -LiteralPath $parent
            }
            Move-Item -LiteralPath $Path -Destination $previous
        }
        Move-Item -LiteralPath $root.FullName -Destination $Path
        Get-ChildItem -LiteralPath $Path -Recurse -File | Unblock-File
        return [pscustomobject]@{ Version = $version; Commit = $commit; Path = $Path; Previous = $(if (Test-Path -LiteralPath $previous) { $previous } else { '' }) }
    } finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Get-NutmegStartChoice {
    # What to start after the download: 'NewForest', 'Window', 'Menu' or 'None'. A workgroup server gets
    # the build (console only); a domain member or DC gets the window, or the menu with -Console.
    param([bool]$PartOfDomain, [switch]$StartBuild, [switch]$Start, [switch]$Console, [switch]$NoStart)
    if ($NoStart) { return 'None' }
    if ($StartBuild) { return 'NewForest' }
    if ($Console) { return 'Menu' }
    if ($Start) { return 'Window' }
    if ($PartOfDomain) { return 'Window' }
    return 'NewForest'
}

function Test-NutmegPartOfDomain {
    # True when this computer is joined to a domain (a DC included).
    try { return [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { return $true }
}

function Update-NutmegSelf {
    <#
    .SYNOPSIS
        Replaces this script with the copy in the toolkit just installed, when it was run from
        somewhere else (C:\Temp, the desktop) and the two differ. Returns the new version, or ''.
    #>
    param([string]$Self, [Parameter(Mandatory)][string]$Path)
    if (-not $Self -or -not (Test-Path -LiteralPath $Self)) { return '' }
    $new = Join-Path $Path 'Get-NutmegAD.ps1'
    if (-not (Test-Path -LiteralPath $new)) { return '' }
    $selfFull = [IO.Path]::GetFullPath($Self); $newFull = [IO.Path]::GetFullPath($new)
    if ($selfFull -eq $newFull) { return '' }
    if ((Get-FileHash -LiteralPath $selfFull).Hash -eq (Get-FileHash -LiteralPath $newFull).Hash) { return '' }
    Copy-Item -LiteralPath $newFull -Destination $selfFull -Force
    $v = if ((Get-Content -LiteralPath $selfFull -Raw) -match "\`$ScriptVersion = '([^']+)'") { $Matches[1] } else { 'new' }
    return $v
}

# Tests dot-source this file with NUTMEG_GET_TEST set, to reach the functions without running it.
if ($env:NUTMEG_GET_TEST) { return }

Clear-Host
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host '   Nutmeg AD Toolkit: get or update' -ForegroundColor Yellow
Write-Host '   Author: Cliff Waite' -ForegroundColor DarkGray
Write-Host '   Email: cliff.ps@nutmegtech.com' -ForegroundColor DarkGray
Write-Host "   Version: $ScriptVersion" -ForegroundColor DarkGray
Write-Host '=============================================' -ForegroundColor Cyan
try { $null = Start-NutmegLog -Folder $LogFolder } catch { Write-Host "No log: $($_.Exception.Message)" -ForegroundColor Yellow }
Write-Step "Get-NutmegAD.ps1 $ScriptVersion on $([Environment]::MachineName) as $([Environment]::UserName). Log: $script:GetLogPath" DarkGray
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
    try {
        $selfVersion = Update-NutmegSelf -Self $PSCommandPath -Path $r.Path
        if ($selfVersion) { Write-Step "This copy of Get-NutmegAD.ps1 ($PSCommandPath) is updated to $selfVersion for next time." DarkGray }
    } catch { Write-Step "This copy of Get-NutmegAD.ps1 was not updated: $($_.Exception.Message)" Yellow }
} catch {
    Write-Step "$($_.Exception.Message)" Red
    return
} finally {
    $token = $null
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
}

$choice = Get-NutmegStartChoice -PartOfDomain (Test-NutmegPartOfDomain) -StartBuild:$StartBuild -Start:$Start -Console:$Console -NoStart:$NoStart
if ($choice -eq 'None') {
    Write-Step "Next: cd '$Path'; .\Start-NutmegAD.ps1 -NewForest   (a new forest),   .\Start-NutmegAD.ps1 -Gui   (the window)   or   .\Start-NutmegAD.ps1   (the menu)" DarkGray
    return
}
Set-Location -LiteralPath $Path
$launchArgs = Get-NutmegLauncherArgs -Choice $choice -LogPath $script:GetLogPath
if ($choice -eq 'NewForest') {
    Write-Step 'This server is in a workgroup: starting the New Forest Build (it carries on in this log).' DarkGray
} elseif ($choice -eq 'Window') {
    Write-Step 'Opening the toolkit window (it carries on in this log). For the console menu: .\Get-NutmegAD.ps1 -Console, or .\Start-NutmegAD.ps1' DarkGray
} else {
    Write-Step 'Starting the toolkit menu (it carries on in this log).' DarkGray
}
& (Join-Path $Path 'Start-NutmegAD.ps1') @launchArgs
