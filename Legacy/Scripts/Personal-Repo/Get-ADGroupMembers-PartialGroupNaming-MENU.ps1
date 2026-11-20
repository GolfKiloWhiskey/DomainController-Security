<# 
.NOTES 
Author: Cliff Waite 
Date: 06/04/2026
Email: cliff.ps@nutmegtech.com
Version: 2.0

.SYNOPSIS
AD Group Member Export Tool (Single or Batch)

.DESCRIPTION
- Menu-driven interactive tool to search for Active Directory Groups.
- Indexed array implementation for granular selection and deep-diving.
- Allows selection of a specific group OR all found groups.
- Dual-Viewing: Outputs to GridView for reference and Console for action.
- Centralized dual-output logging system (Console and File).
- Formats exports automatically to default or custom paths.

.EXAMPLE
.\ADGroupExportTool.ps1

.VERSIONING 
2.0 - Complete rewrite to comply with updated scripting standards, including dual-output logging, indexed arrays, module auto-installation, and Result Action Menus.
1.1 - Added CSV export capabilities.
1.0 - Initial script creation.
#>

$ScriptVersion = "2.0"
$Global:ExportDir = "C:\Temp"
$Global:LogDir = "C:\Temp\Logs"
if (-not (Test-Path $Global:LogDir)) { New-Item -ItemType Directory -Path $Global:LogDir -Force | Out-Null }
$Global:LogFile = Join-Path $Global:LogDir "ADGroupExport_Log_$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

# ---------------------------------------------------------------------------
# Helpers & Logging
# ---------------------------------------------------------------------------
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"

    $Color = switch ($Level) {
        'INFO'  { 'Cyan' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
    }

    Write-Host $LogEntry -ForegroundColor $Color
    $LogEntry | Out-File -FilePath $global:LogFile -Append -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------
try {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Log -Message "ActiveDirectory module is missing. Attempting to install RSAT tools..." -Level WARN
        
        try {
            # Attempt Windows 10/11 Capability Install
            Add-WindowsCapability -Online -Name RsaT.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 -ErrorAction Stop | Out-Null
        } catch {
            # Fallback to Server Feature Install
            Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature -ErrorAction Stop | Out-Null
        }
        Write-Log -Message "ActiveDirectory module installed successfully." -Level INFO
    }
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log -Message "Failed to load or install ActiveDirectory module. Ensure you run as Administrator. Details: $_" -Level ERROR
    Exit
}

# ---------------------------------------------------------------------------
# Menus
# ---------------------------------------------------------------------------
function Show-MainMenu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   AD GROUP MEMBER EXPORT UTILITY            " -ForegroundColor Yellow
    Write-Host "   Author: Cliff Waite                       " -ForegroundColor DarkGray
    Write-Host "   Email:cliff.ps@nutmegtech.com             " -ForegroundColor DarkGray
    Write-Host "   Version: $ScriptVersion                   " -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Search and Export AD Groups" -ForegroundColor Cyan
    Write-Host "Q. Quit" -ForegroundColor Red
    Write-Host ""
}

function Show-ResultMenu {
    param([array]$Data)
    
    while ($true) {
        Write-Host "`n=============================================" -ForegroundColor Cyan
        Write-Host "   RESULT ACTION MENU                        " -ForegroundColor Yellow
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host "1. Export Results to CSV" -ForegroundColor Cyan
        Write-Host "2. Deep-Dive into specific item via [#]" -ForegroundColor Cyan
        Write-Host "3. Return to Main Menu" -ForegroundColor Cyan
        Write-Host ""
        
        $action = Read-Host "Select an option (Press Enter for Default: 3)"
        
        if ([string]::IsNullOrWhiteSpace($action) -or $action -eq '3') { break }
        
        if ($action -eq '1') {
            $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $ExportPath = Read-Host "Enter export directory (Press Enter for Default: $Global:ExportDir)"
            
            if ([string]::IsNullOrWhiteSpace($ExportPath)) { $ExportPath = $Global:ExportDir }
            if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
            
            $File = Join-Path $ExportPath "ADGroupExport_$Timestamp.csv"
            try {
                # Strip out the indexing column before final export
                $Data | Select-Object * -ExcludeProperty "[#]" | Export-Csv -Path $File -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                Write-Log -Message "Successfully exported to $File" -Level INFO
            } catch {
                Write-Log -Message "Failed to export CSV: $_" -Level ERROR
            }
        }
        elseif ($action -eq '2') {
            $idx = Read-Host "Enter the [#] of the item to deep dive"
            $selected = $Data | Where-Object { $_."[#]" -eq $idx }
            
            if ($selected) {
                Write-Host "`n--- Deep Dive Details ---" -ForegroundColor Cyan
                $selected | Select-Object * -ExcludeProperty "[#]" | Format-List | Out-String | Write-Host -ForegroundColor Green
            } else {
                Write-Log -Message "Invalid selection [#]." -Level WARN
            }
        }
        else {
            Write-Log -Message "Invalid input." -Level WARN
        }
    }
}

# ---------------------------------------------------------------------------
# Main Logic
# ---------------------------------------------------------------------------
while ($true) {
    Show-MainMenu
    $mainChoice = Read-Host "Select an option (1 or Q)"
    
    if ($mainChoice -eq 'Q') {
        Write-Log -Message "Exiting script..." -Level INFO
        break
    }
    if ($mainChoice -ne '1') { continue }

    # --- Phase 1: Search ---
    Write-Host "`nEnter partial group name to search." -ForegroundColor Yellow
    Write-Host "(Press Enter to search specifically for 'VPN')" -ForegroundColor DarkGray
    $SearchInput = Read-Host "Search"

    $SearchTerm = if ([string]::IsNullOrWhiteSpace($SearchInput)) { "*VPN*" } else { "*$SearchInput*" }
    Write-Log -Message "Searching AD for groups matching '$SearchTerm'..." -Level INFO

    try {
        $FoundGroups = Get-ADGroup -Filter "Name -like '$SearchTerm'" -Properties Description -ErrorAction Stop
        
        if (-not $FoundGroups) {
            Write-Log -Message "No groups found matching '$SearchTerm'." -Level WARN
            Start-Sleep -Seconds 2
            continue
        }

        # Build Indexed Array for Groups
        $IndexedGroups = [System.Collections.Generic.List[PSObject]]::new()
        $gCounter = 1
        foreach ($g in $FoundGroups) {
            $IndexedGroups.Add([PSCustomObject]@{
                '[#]'               = $gCounter
                'Name'              = $g.Name
                'Description'       = $g.Description
                'RawObject'         = $g
            })
            $gCounter++
        }

        Write-Host "`nFound $($IndexedGroups.Count) group(s):" -ForegroundColor Cyan
        $IndexedGroups | Select-Object "[#]", Name, Description | Format-Table -AutoSize

        Write-Host "[A] PROCESS ALL GROUPS LISTED ABOVE" -ForegroundColor Yellow
        Write-Host "[Q] CANCEL AND RETURN TO MAIN MENU" -ForegroundColor Red
        
        $sel = Read-Host "Select a group [#], 'A' for All, or 'Q' to quit"
        if ($sel -eq 'Q') { continue }
        
        $GroupsToProcess = @()
        if ($sel -eq 'A') {
            $GroupsToProcess = $FoundGroups
        } else {
            $selectedGroup = $IndexedGroups | Where-Object { $_."[#]" -eq $sel }
            if ($selectedGroup) {
                $GroupsToProcess = @($selectedGroup.RawObject)
            } else {
                Write-Log -Message "Invalid group selection. Returning to menu." -Level WARN
                Start-Sleep -Seconds 2
                continue
            }
        }

        # --- Phase 2: Data Retrieval ---
        $MasterList = [System.Collections.Generic.List[PSObject]]::new()
        $mCounter = 1

        foreach ($Group in $GroupsToProcess) {
            Write-Log -Message "Processing members for group: $($Group.Name)..." -Level INFO
            
            $Members = Get-ADGroupMember -Identity $Group -ErrorAction SilentlyContinue | Where-Object { $_.objectClass -eq "user" }
            
            if ($Members) {
                try {
                    $UserDetails = $Members | Get-ADUser -Properties UserPrincipalName -ErrorAction Stop
                    
                    foreach ($User in $UserDetails) {
                        $Obj = [PSCustomObject]@{
                            '[#]'               = $mCounter
                            'Source Group'      = $Group.Name
                            'Full Name'         = $User.Name
                            'UserPrincipalName' = $User.UserPrincipalName
                            'DistinguishedName' = $User.DistinguishedName
                        }
                        $MasterList.Add($Obj)
                        $mCounter++
                    }
                } catch {
                    Write-Log -Message "Error retrieving user details for group $($Group.Name): $_" -Level ERROR
                }
            } else {
                Write-Host "  -> No user members found in $($Group.Name)" -ForegroundColor DarkGray
            }
        }

        # --- Phase 3: Output & Action ---
        if ($MasterList.Count -gt 0) {
            Write-Log -Message "Total user records found: $($MasterList.Count)" -Level INFO
            
            # Dual-Viewing: Reference Window (Out-GridView) + Console
            $MasterList | Out-GridView -Title "Group Export Results - $($MasterList.Count) Items" -PassThru:$false
            
            Write-Host "`n--- Data Results ---" -ForegroundColor Cyan
            # Showing top 25 in console if array is huge to prevent overwhelming the screen, but standard is Format-Table
            if ($MasterList.Count -gt 25) { Write-Host "Showing top 25 records in console (View GridView for all)..." -ForegroundColor DarkGray }
            $MasterList | Select-Object -First 25 | Format-Table -AutoSize
            
            Show-ResultMenu -Data $MasterList
        } else {
            Write-Log -Message "No user members found in selected group(s)." -Level WARN
            Start-Sleep -Seconds 2
        }
        
    } catch {
        Write-Log -Message "An error occurred during AD querying: $_" -Level ERROR
        Start-Sleep -Seconds 3
    }
}