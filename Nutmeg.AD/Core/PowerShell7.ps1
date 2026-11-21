# ---------------------------------------------------------------------------
# PowerShell7.ps1 - find PowerShell 7, or install the current LTS release from Microsoft
# ---------------------------------------------------------------------------
# A newly built DC has only Windows PowerShell 5.1. The launcher starts there and offers to move to
# PowerShell 7. The install:
# - takes the LTS version from PowerShell's own release metadata (metadata.json in the PowerShell repo);
# - downloads Microsoft's MSI from the PowerShell GitHub release;
# - refuses to run it unless its Authenticode signature is valid and Microsoft's;
# - installs with Microsoft Update turned on (USE_MU=1 ENABLE_MU=1), so PowerShell 7 is patched like
#   the rest of Windows, and adds pwsh to PATH.
# Logging for PowerShell 7 is the GPO baseline's job (Security - PowerShell Logging), not this file's.

$script:NmPwshMetadataUri = 'https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/metadata.json'

function Find-NmPwsh {
    # The path to pwsh.exe, or $null when PowerShell 7 is not installed.
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $cmd = Get-Command -Name pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    if ($env:ProgramFiles) {
        $p = Join-Path (Join-Path (Join-Path $env:ProgramFiles 'PowerShell') '7') 'pwsh.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Enable-NmTls12 {
    # Windows PowerShell 5.1 on older Windows may not offer TLS 1.2, which GitHub requires.
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { $null = $_ }
    }
}

function Save-NmDownload {
    <#
    .SYNOPSIS
        Downloads a file with the progress bar off, then logs its size and how long it took.
    .DESCRIPTION
        Windows PowerShell 5.1 redraws Invoke-WebRequest's progress bar for every chunk it receives,
        which slows a large download to a few hundred KB/s (the same file comes down at full speed in
        a browser). With the bar off it runs at the connection's speed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$OutFile, [int]$TimeoutSec = 600)
    $ProgressPreference = 'SilentlyContinue'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
    $sw.Stop()
    $mb = if (Test-Path -LiteralPath $OutFile) { [math]::Round((Get-Item -LiteralPath $OutFile).Length / 1MB, 1) } else { 0 }
    Write-NmLog "Downloaded $mb MB in $([math]::Round($sw.Elapsed.TotalSeconds, 1)) s." -Level INFO
}

function Get-NmPwshLtsVersion {
    <#
    .SYNOPSIS
        The current PowerShell LTS version (7.6.10), from PowerShell's release metadata.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    Enable-NmTls12
    $ProgressPreference = 'SilentlyContinue'
    $meta = Invoke-RestMethod -Uri $script:NmPwshMetadataUri -TimeoutSec 30 -ErrorAction Stop
    $tag = "$(@($meta.LTSReleaseTag)[0])"
    if ($tag -notmatch '^v?(\d+\.\d+\.\d+)$') { throw "PowerShell's release metadata gave no LTS version ('$tag')." }
    return $Matches[1]
}

function Get-NmPwshMsiUri {
    # The MSI for a version and this computer's processor.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Version, [string]$Arch = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }))
    return "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-win-$Arch.msi"
}

function Test-NmMicrosoftSignature {
    # True when a file's Authenticode signature is valid and signed by Microsoft Corporation.
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)
    $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
    return ("$($sig.Status)" -eq 'Valid' -and "$($sig.SignerCertificate.Subject)" -match 'O=Microsoft Corporation')
}

function Install-NmPowerShell7 {
    <#
    .SYNOPSIS
        Downloads and installs the current PowerShell 7 LTS release, with Microsoft Update turned on.
    .OUTPUTS
        One row: Item, Version, Result ("Installed", "WhatIf: not changed", "Cancelled", "Failed: reason").
    .EXAMPLE
        Install-NmPowerShell7
    .EXAMPLE
        Install-NmPowerShell7 -ApprovedBy 'Get-NutmegAD.ps1: PowerShell 7 is part of every toolkit server'
        Installs without asking (Cliff's rule for Get-NutmegAD.ps1); the approval is logged.
    #>
    [CmdletBinding()]
    param([string]$Version, [switch]$WhatIf, [string]$ApprovedBy)

    $row = { param($v, $r) [pscustomobject]@{ Item = 'PowerShell 7'; Version = $v; Result = $r } }
    if (-not $script:NmOnWindows) { return (& $row $Version 'Failed: PowerShell 7 can only be installed this way on Windows') }
    if (-not (Test-NmElevated)) { return (& $row $Version 'Failed: run the toolkit as administrator to install PowerShell 7') }
    try {
        if (-not $Version) { $Version = Get-NmPwshLtsVersion }
    } catch {
        return (& $row '' "Failed: could not read the current version ($($_.Exception.Message))")
    }
    $uri = Get-NmPwshMsiUri -Version $Version

    # -ApprovedBy: approved beforehand, so Confirm-NmChange shows and logs the change without asking.
    $wasPlan = $script:NmPlanApproved
    if ($ApprovedBy) { Set-NmPlanApproved -Plan $ApprovedBy }
    try {
        $ok = Confirm-NmChange -Action "Install PowerShell $Version on $([Environment]::MachineName) (Microsoft Update on)" -Targets @($uri) -WhatIf:$WhatIf
    } finally { Set-NmPlanApproved -Plan $wasPlan }
    if (-not $ok) {
        $r = if ($WhatIf) { 'WhatIf: not changed' } else { 'Cancelled' }
        return (& $row $Version $r)
    }

    $msi = Join-Path ([System.IO.Path]::GetTempPath()) "PowerShell-$Version.msi"
    try {
        Enable-NmTls12
        Write-NmLog "Downloading PowerShell $Version..." -Level INFO
        Save-NmDownload -Uri $uri -OutFile $msi
        if (-not (Test-NmMicrosoftSignature -Path $msi)) {
            Write-NmRunHistory -ToolId 'install-pwsh' -Kind Change -Result Failed -Notes 'Signature not valid'
            return (& $row $Version 'Failed: the download is not signed by Microsoft, so it was not run')
        }
        Write-NmLog "Installing PowerShell $Version (Microsoft Update on, added to PATH)..." -Level INFO
        $msiArgs = @('/i', "`"$msi`"", '/qn', '/norestart', 'ADD_PATH=1', 'USE_MU=1', 'ENABLE_MU=1', 'REGISTER_MANIFEST=1')
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -ErrorAction Stop
        # 0 = done; 3010 = done, a restart finishes it.
        if (@(0, 3010) -notcontains [int]$p.ExitCode) {
            Write-NmRunHistory -ToolId 'install-pwsh' -Kind Change -Result Failed -Notes "msiexec exit $($p.ExitCode)"
            return (& $row $Version "Failed: the installer stopped with code $($p.ExitCode)")
        }
        Write-NmRunHistory -ToolId 'install-pwsh' -Kind Change -ItemCount 1 -Notes "PowerShell $Version"
        Write-NmLog "PowerShell $Version installed." -Level SUCCESS
        return (& $row $Version $(if ([int]$p.ExitCode -eq 3010) { 'Installed (restart to finish)' } else { 'Installed' }))
    } catch {
        Write-NmRunHistory -ToolId 'install-pwsh' -Kind Change -Result Failed -Notes $_.Exception.Message
        return (& $row $Version "Failed: $($_.Exception.Message)")
    } finally {
        if (Test-Path -LiteralPath $msi) { Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue }
    }
}
