# ---------------------------------------------------------------------------
# Export.ps1 - CSV/TXT exports to C:\Temp with timestamped file names
# ---------------------------------------------------------------------------

function Get-NmCsvArgs {
    # -NoTypeInformation is needed on Windows PowerShell 5.1 but warns as obsolete on PowerShell 7.7+.
    # UTF-8 with a byte-order mark, so Excel reads accented names correctly ('UTF8' has no BOM on PowerShell 7).
    $csvArgs = @{ Encoding = $(if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' }); ErrorAction = 'Stop' }
    if ($PSVersionTable.PSVersion.Major -lt 6) { $csvArgs.NoTypeInformation = $true }
    return $csvArgs
}

function Get-NmExportFileName {
    <#
    .SYNOPSIS
        Builds "<ToolId>_<Domain>_yyyyMMdd-HHmm-ss.<ext>", safe for any file system.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [string]$Domain,
        [ValidateSet('csv', 'txt')][string]$Extension = 'csv',
        [datetime]$Time = (Get-Date)
    )

    $domainPart = if ($Domain) { ($Domain -split '\.')[0] } else { 'NoDomain' }
    $raw = '{0}_{1}_{2}.{3}' -f $ToolId, $domainPart, $Time.ToString('yyyyMMdd-HHmm-ss'), $Extension
    $invalid = [regex]::Escape(-join [System.IO.Path]::GetInvalidFileNameChars())
    return ($raw -replace "[$invalid]", '-')
}

function Export-NmResult {
    <#
    .SYNOPSIS
        Exports results to CSV or TXT. Prompts for the folder (default C:\Temp) unless -Path or -NoPrompt is given.
    .OUTPUTS
        The full path of the file written, or $null on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Data,
        [Parameter(Mandatory)][string]$ToolId,
        [ValidateSet('Csv', 'Txt')][string]$Format = 'Csv',
        [string]$Path,
        [switch]$NoPrompt
    )

    if (-not $Data -or $Data.Count -eq 0) {
        Write-NmLog 'Nothing to export.' -Level WARN
        return $null
    }

    $folder = $Path
    if (-not $folder) {
        if ($NoPrompt) {
            $folder = $script:NmConfig.ExportRoot
        } else {
            $folder = Read-NmInput -Prompt 'Export folder' -Default $script:NmConfig.ExportRoot
        }
    }

    try {
        if (-not (Test-Path $folder)) {
            New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $fileName = Get-NmExportFileName -ToolId $ToolId -Domain (Get-NmSession).Domain -Extension $Format.ToLower()
        $fullPath = Join-Path $folder $fileName

        # The [#] column is for picking rows on screen; it has no place in an export.
        $clean = $Data | Select-Object -Property * -ExcludeProperty '#'

        if ($Format -eq 'Csv') {
            $csvArgs = Get-NmCsvArgs
            $clean | Export-Csv -Path $fullPath @csvArgs
        } else {
            $clean | Microsoft.PowerShell.Utility\Format-Table -AutoSize | Out-String -Width 4096 |
                Set-Content -Path $fullPath -Encoding UTF8 -ErrorAction Stop
        }

        Write-NmLog "Exported $($Data.Count) rows to $fullPath" -Level SUCCESS
        return $fullPath
    } catch {
        Write-NmLog "Export failed: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}
