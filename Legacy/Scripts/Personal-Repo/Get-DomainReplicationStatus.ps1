[CmdletBinding()]
param (
    [Parameter()]
    [int]$EventLogStart = 168,
    [Parameter()]
    [int]$ErrorCount = 100,
    [Parameter()]
    [String]$EventLogCustomField,
    [Parameter()]
    [String]$ErrorCustomField,
    [Parameter()]
    [String]$ExportCSV,
    [Parameter()]
    [String]$ExportTXT
)

begin {
    function Test-IsElevated {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Test-IsSystem {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        return $id.Name -like "NT AUTHORITY*" -or $id.IsSystem
    }

    function Test-IsDomainController {
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem
        return $OS.ProductType -eq 2
    }

    if (!(Test-IsElevated) -and !(Test-IsSystem)) {
        Write-Error "Access Denied. Please run with Administrator privileges."
        exit 1
    }

    if (!(Test-IsDomainController)) {
        Write-Error "This is not a domain controller. Please run this script on a DC."
        exit 1
    }

    # Override parameters with environment variables if they are set
    $EventLogStart = if ($env:hoursBackToSearchEventLog -and $env:hoursBackToSearchEventLog -ne "null") { $env:hoursBackToSearchEventLog } else { $EventLogStart }
    $ErrorCount = if ($env:errorCountToAlertOn -and $env:errorCountToAlertOn -ne "null") { $env:errorCountToAlertOn } else { $ErrorCount }
    $EventLogCustomField = if ($env:retrieveHoursBackFromCustomFieldNamed -and $env:retrieveHoursBackFromCustomFieldNamed -ne "null") { $env:retrieveHoursBackFromCustomFieldNamed } else { $EventLogCustomField }
    $ErrorCustomField = if ($env:retrieveErrorCountFromCustomFieldNamed -and $env:retrieveErrorCountFromCustomFieldNamed -ne "null") { $env:retrieveErrorCountFromCustomFieldNamed } else { $ErrorCustomField }
    $ExportCSV = if ($env:exportCsvResultsToThisCustomField -and $env:exportCsvResultsToThisCustomField -ne "null") { $env:exportCsvResultsToThisCustomField } else { $ExportCSV }
    $ExportTXT = if ($env:exportTextResultsToThisCustomField -and $env:exportTextResultsToThisCustomField -ne "null") { $env:exportTextResultsToThisCustomField } else { $ExportTXT }

    $ExitCode = 0
}

process {
    Write-Host "Starting AD Replication Health Check..." -ForegroundColor Green

    $represult = repadmin.exe /showrepl /csv | ConvertFrom-Csv

    if ($ExportCSV) {
        try {
            repadmin.exe /showrepl /csv | Set-Content -Path $ExportCSV
            Write-Host "Replication data exported to CSV at $ExportCSV" -ForegroundColor Green
        } catch {
            Write-Error "Failed to export CSV: $_"
            $ExitCode = 1
        }
    }

    if ($ExportTXT) {
        $String = $represult | Format-Table -Property "Destination DSA", "Last Success Time", "Last Failure Status", "Number of Failures", "Naming Context" | Out-String
        try {
            $String | Set-Content -Path $ExportTXT
            Write-Host "Replication data exported to TXT at $ExportTXT" -ForegroundColor Green
        } catch {
            Write-Error "Failed to export TXT: $_"
            $ExitCode = 1
        }
    }

    Write-Host "Replication Details:" -ForegroundColor Cyan
    $represult | Format-Table -AutoSize | Out-String | Write-Host

    if ($represult."Number of Failures" -ge $ErrorCount) {
        Write-Warning "Replication has failed $ErrorCount or more times. See Diagnostic Info for more details."
        Write-Host '### Diagnostic Info ###' -ForegroundColor Yellow
        repadmin.exe /showrepl /errorsonly
        $represult | Format-Table -Property "Destination DSA", "Last Success Time", @{Name="Failures";Expression={$_."Number of Failures"}}, "Naming Context" | Out-String | Write-Host
        Exit 1
    } else {
        Write-Host "No errors found in repadmin /showrepl /csv" -ForegroundColor Green
    }

    # Additional Replication Information
    Write-Host "Gathering Additional Replication Information..." -ForegroundColor Green

    $repsummary = repadmin.exe /replsummary | Out-String
    Write-Host "Replication Summary:" -ForegroundColor Cyan
    Write-Host $repsummary

    $kccerrors = repadmin.exe /kcc | Out-String
    Write-Host "KCC Errors:" -ForegroundColor Cyan
    Write-Host $kccerrors

    $showconn = repadmin.exe /showconn | Out-String
    Write-Host "Connection Objects:" -ForegroundColor Cyan
    Write-Host $showconn

    $namingContexts = (Get-ADRootDSE).namingContexts
    foreach ($nc in $namingContexts) {
        $showutdvec = repadmin.exe /showutdvec * $nc | Out-String
        Write-Host "Up-to-Dateness Vectors for Naming Context $nc" -ForegroundColor Cyan
        Write-Host $showutdvec
    }

    $showrepl = repadmin.exe /showrepl * | Out-String
    Write-Host "Replication Topology:" -ForegroundColor Cyan
    Write-Host $showrepl

    # Check Event Log for replication failure
    $Date = (Get-Date).AddHours(-$EventLogStart)
    $Events = Get-WinEvent -FilterHashtable @{LogName = "Directory Service"; Id = 1864; StartTime = $Date } -ErrorAction SilentlyContinue | 
              Where-Object { $_.Message -replace "`r`n", " " -match "More than a week: [1-9]+.*" }

    if ($Events) {
        Write-Warning "Directory Service Log Event ID 1864 shows failure to replicate in > 1 week"
        $Events | Format-Table -Property TimeCreated, Id, LogName, @{Name="Level";Expression={$_.LevelDisplayName}}, Message -AutoSize | Out-String | Write-Host
        Exit 1
    } else {
        Write-Host "No bad event viewer events found since $Date." -ForegroundColor Green
    }

    # Check if SYSVOL is present
    $sysvol = Get-CimInstance Win32_Share | Where-Object { $_.Name -eq "SYSVOL" }
    if (!($sysvol.Path)) {
        Write-Warning "SYSVOL is Missing!"
        Get-CimInstance Win32_Share | Out-String | Write-Host
        Exit 1
    } else {
        Write-Host "SYSVOL appears to be present." -ForegroundColor Green
    }

    Write-Host "AD Replication appears to be healthy. Please check script output and other sources to confirm." -ForegroundColor Green
    $Report = $represult | Format-Table -Property "Destination DSA", "Last Success Time", @{Name="Failures";Expression={$_."Number of Failures"}}, "Naming Context" | Out-String
    if ($Report) {
        $Report | Write-Host
    }

    # Exit with the appropriate code
   # exit $ExitCode
}

end {

}
