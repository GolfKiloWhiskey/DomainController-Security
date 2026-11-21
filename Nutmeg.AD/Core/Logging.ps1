# ---------------------------------------------------------------------------
# Logging.ps1 - Write-NmLog (console + .txt log) and the run history CSV
# ---------------------------------------------------------------------------

$script:NmLogPath = $null

$script:NmLevelColors = @{
    INFO    = 'Cyan'
    WARN    = 'Yellow'
    ERROR   = 'Red'
    SUCCESS = 'Green'
    DETAIL  = 'DarkGray'
}

function Get-NmContinuedLogPath {
    <#
    .SYNOPSIS
        The log this session should carry on in, or $null for a new one.
    .DESCRIPTION
        - NUTMEG_AD_LOG: set by Start-NutmegAD.ps1 -LogPath (Get-NutmegAD.ps1 passes the log it started).
        - Otherwise, a New Forest Build still running on this server: its log, from the state file, so
          the sessions after each restart write to the same file.
    #>
    [CmdletBinding()]
    param()
    if ($env:NUTMEG_AD_LOG) { return $env:NUTMEG_AD_LOG }
    try {
        if (Get-Command Get-NmBuildState -ErrorAction SilentlyContinue) {
            $state = Get-NmBuildState
            if ($state -and -not $state.Finished -and $state.PSObject.Properties['LogPath'] -and "$($state.LogPath)" -and (Test-Path -LiteralPath "$($state.LogPath)")) {
                return "$($state.LogPath)"
            }
        }
    } catch { $null = $_ }
    return $null
}

function Get-NmLogPath {
    <#
    .SYNOPSIS
        Returns this session's log file path, creating the log folder on first use.
    .DESCRIPTION
        Carries on in an earlier log when there is one to continue (Get-NmContinuedLogPath), with a
        line marking where this session starts; otherwise starts NutmegAD_<time>.txt.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:NmLogPath) {
        $continued = Get-NmContinuedLogPath
        if ($continued) {
            $dir = Split-Path -Parent $continued
            if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
            $script:NmLogPath = $continued
            $ps = "$(if ($PSVersionTable.PSVersion.Major -ge 6) { 'PowerShell' } else { 'Windows PowerShell' }) $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
            $marker = Format-NmLogLine -Message "---- Session continued: $([Environment]::UserName) on $([Environment]::MachineName), $ps, toolkit $script:ModuleVersion ----" -Level INFO
            try { Add-Content -Path $continued -Value $marker -Encoding UTF8 -ErrorAction Stop } catch { $null = $_ }
        } else {
            $logDir = Join-Path $script:NmConfig.DataRoot 'Logs'
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            $stamp = Get-Date -Format 'yyyyMMdd-HHmm-ss'
            $script:NmLogPath = Join-Path $logDir "NutmegAD_$stamp.txt"
        }
    }
    return $script:NmLogPath
}

function Format-NmLogLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Level,
        [datetime]$Time = (Get-Date)
    )
    return '[{0}] [{1}] {2}' -f $Time.ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
}

function Write-NmLog {
    <#
    .SYNOPSIS
        Writes "[YYYY-MM-DD HH:MM:SS] [LEVEL] Message" to the console in colour and to the session log file.
    .PARAMETER Level
        INFO (Cyan), WARN (Yellow), ERROR (Red), SUCCESS (Green), DETAIL (DarkGray).
    .PARAMETER NoConsole
        Write to the log file only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Message,
        [Parameter(Position = 1)][ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DETAIL')][string]$Level = 'INFO',
        [switch]$NoConsole
    )

    $line = Format-NmLogLine -Message $Message -Level $Level

    if (-not $NoConsole) {
        Write-Host $line -ForegroundColor $script:NmLevelColors[$Level]
    }

    try {
        Add-Content -Path (Get-NmLogPath) -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Logging must never stop a tool; say so once on screen and carry on.
        if (-not $script:NmLogWarned) {
            Write-Host "[WARN] Could not write to log file: $($_.Exception.Message)" -ForegroundColor Yellow
            $script:NmLogWarned = $true
        }
    }
}

# ---------------------------------------------------------------------------
# Run history: one row per tool run
# ---------------------------------------------------------------------------

function Get-NmRunHistoryPath {
    [CmdletBinding()]
    param()
    if (-not (Test-Path $script:NmConfig.DataRoot)) {
        New-Item -Path $script:NmConfig.DataRoot -ItemType Directory -Force | Out-Null
    }
    return (Join-Path $script:NmConfig.DataRoot 'History.csv')
}

function Write-NmRunHistory {
    <#
    .SYNOPSIS
        Appends one row to History.csv: who ran which tool against which domain, and what came of it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [string]$ToolVersion = '',
        [ValidateSet('Report', 'Change', 'ReportAndChange')][string]$Kind = 'Report',
        [ValidateSet('Run', 'WhatIf', 'Cancelled')][string]$Mode = 'Run',
        [int]$ItemCount = 0,
        [ValidateSet('Success', 'Failed', 'Cancelled')][string]$Result = 'Success',
        [string]$Notes = ''
    )

    $session = Get-NmSession
    $row = [pscustomobject]@{
        Timestamp   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        User        = [Environment]::UserName
        Computer    = [Environment]::MachineName
        Domain      = $session.Domain
        Server      = $session.Server
        ToolId      = $ToolId
        ToolVersion = $ToolVersion
        Kind        = $Kind
        Mode        = $Mode
        ItemCount   = $ItemCount
        Result      = $Result
        Notes       = $Notes
    }

    try {
        $csvArgs = Get-NmCsvArgs
        $row | Export-Csv -Path (Get-NmRunHistoryPath) -Append @csvArgs
    } catch {
        Write-NmLog "Could not write run history: $($_.Exception.Message)" -Level WARN
    }
}

function Get-NmRunHistory {
    <#
    .SYNOPSIS
        Returns the most recent run history rows, newest first.
    #>
    [CmdletBinding()]
    param([int]$Last = 25)

    $path = Get-NmRunHistoryPath
    if (-not (Test-Path $path)) { return @() }
    $rows = @(Import-Csv -Path $path)
    [array]::Reverse($rows)
    return $rows | Select-Object -First $Last
}
