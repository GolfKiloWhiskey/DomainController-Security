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

function Get-NmLogPath {
    <#
    .SYNOPSIS
        Returns this session's log file path, creating the log folder on first use.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:NmLogPath) {
        $logDir = Join-Path $script:NmConfig.DataRoot 'Logs'
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmm-ss'
        $script:NmLogPath = Join-Path $logDir "NutmegAD_$stamp.txt"
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
