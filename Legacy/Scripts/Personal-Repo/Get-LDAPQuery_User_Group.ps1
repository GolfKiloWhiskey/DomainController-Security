<#
.NOTES 
Author: Cliff Waite 
Date: 09/16/2026
Email: cliff.ps@nutmegtech.com
Version: 1.2

.SYNOPSIS
Queries Active Directory user and group information natively from a member server without requiring the AD Module.

.DESCRIPTION
- Utilizes native [adsisearcher] (ADSI) to query AD without needing RSAT or remote server management.
- Features a menu-driven interface to search for users, groups, and group memberships.
- Standardized logging system to console and text file.
- Action menus for detailed deep-dives into specific AD objects and easy CSV exporting.
- Error handling and graceful fallbacks for missing data.
- Automatic wildcards for seamless partial matching.

.EXAMPLE
.\Get-NativeADInfo.ps1

.VERSIONING 
1.2 - Added automatic wildcards to LDAP filters for seamless partial string matching.
1.1 - Added 2-character minimum validation and multi-select sub-menu for group member searches.
1.0 - Initial release with ADSI searcher, logging, and export capabilities.
#>

# ---------------------------------------------------------------------------
# GLOBAL VARIABLES & SETUP
# ---------------------------------------------------------------------------
$ScriptVersion = "1.2"
$ExportPath = "C:\Temp"
$LogFile = "$ExportPath\ADQueryLog-$(Get-Date -Format 'yyyyMMdd').txt"

if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath | Out-Null
}

# ---------------------------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    # Write to File
    Add-Content -Path $LogFile -Value $LogEntry
    
    # Write to Console with Colors
    switch ($Level) {
        'INFO'  { Write-Host $LogEntry -ForegroundColor Cyan }
        'WARN'  { Write-Host $LogEntry -ForegroundColor Yellow }
        'ERROR' { Write-Host $LogEntry -ForegroundColor Red }
    }
}

function Invoke-AdsiQuery {
    param (
        [string]$LdapFilter,
        [string]$Context = "Search"
    )
    
    try {
        Write-Log -Message "Executing LDAP Query: $LdapFilter" -Level INFO
        $Searcher = [adsisearcher]$LdapFilter
        $Searcher.PageSize = 1000
        $Results = $Searcher.FindAll()
        
        if ($Results.Count -eq 0) {
            Write-Log -Message "No results found for query." -Level WARN
            return $null
        }

        $Output = @()
        $Index = 1
        
        foreach ($Res in $Results) {
            # Create Custom Object and inject Index for Action Menu
            $Obj = [PSCustomObject]@{ '#' = $Index }
            
            foreach ($Prop in $Res.Properties.PropertyNames) {
                if ($Prop -ne "adspath") {
                    $Value = $Res.Properties[$Prop]
                    # Handle multi-value properties (like proxyAddresses or memberOf)
                    if ($Value.Count -gt 1) { 
                        $Value = $Value -join "; " 
                    }
                    $Obj | Add-Member -MemberType NoteProperty -Name $Prop -Value $Value
                }
            }
            $Output += $Obj
            $Index++
        }
        
        Write-Log -Message "Found $($Output.Count) result(s) for $Context." -Level INFO
        return $Output
    }
    catch {
        Write-Log -Message "Error executing ADSI query: $_" -Level ERROR
        return $null
    }
}

function Show-ResultMenu {
    param (
        [array]$DataList,
        [string]$ContextName
    )
    
    if (-not $DataList) {
        Write-Host "Press Enter to return to the main menu..." -ForegroundColor DarkGray
        Pause
        return
    }

    $Continue = $true
    while ($Continue) {
        Write-Host "`n--- RESULT ACTION MENU ---" -ForegroundColor Yellow
        Write-Host "[#] Enter the index number to Deep-Dive into an item's full properties" -ForegroundColor Cyan
        Write-Host "[E] Export results to CSV" -ForegroundColor Cyan
        Write-Host "[V] View results in GridView again" -ForegroundColor Cyan
        Write-Host "[R] Return to Main Menu" -ForegroundColor Cyan
        
        $Choice = Read-Host "`nSelect an action (Default: R)"
        if ([string]::IsNullOrWhiteSpace($Choice)) { $Choice = 'R' }

        switch -Regex ($Choice) {
            '^[0-9]+$' {
                $Index = [int]$Choice
                $SelectedItem = $DataList | Where-Object { $_.'#' -eq $Index }
                if ($SelectedItem) {
                    Write-Host "`n--- DEEP DIVE: Item #$Index ---" -ForegroundColor Cyan
                    $SelectedItem | Format-List
                } else {
                    Write-Host "Invalid index number." -ForegroundColor Yellow
                }
            }
            '^[eE]$' {
                $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $CsvPath = "$ExportPath\$ContextName-$Timestamp.csv"
                try {
                    $DataList | Export-Csv -Path $CsvPath -NoTypeInformation
                    Write-Host "Successfully exported to: $CsvPath" -ForegroundColor Green
                    Write-Log -Message "Exported $ContextName results to $CsvPath" -Level INFO
                } catch {
                    Write-Log -Message "Failed to export CSV: $_" -Level ERROR
                }
            }
            '^[vV]$' {
                $DataList | Out-GridView -Title "$ContextName Results"
            }
            '^[rR]$' {
                $Continue = $false
            }
            default {
                Write-Host "Invalid selection. Please try again." -ForegroundColor Yellow
            }
        }
    }
}

# ---------------------------------------------------------------------------
# MAIN LOGIC & MENUS
# ---------------------------------------------------------------------------
function Show-MainMenu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   NATIVE ADSI QUERY TOOL                    " -ForegroundColor Yellow
    Write-Host "   Author: Cliff Waite                       " -ForegroundColor DarkGray
    Write-Host "   Email: cliff.ps@nutmegtech.com            " -ForegroundColor DarkGray
    Write-Host "   Version: $ScriptVersion                   " -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "1. Search for a User"
    Write-Host "2. Search for a Group"
    Write-Host "3. List Members of a Group"
    Write-Host "4. Custom LDAP Query"
    Write-Host "Q. Quit"
    Write-Host "=============================================" -ForegroundColor Cyan
}

# Ensure Log File exists and start session
Write-Log -Message "--- Starting Native AD Query Session v$ScriptVersion ---" -Level INFO

$ScriptActive = $true
while ($ScriptActive) {
    Show-MainMenu
    $MenuSelection = Read-Host "Select an option"
    
    switch ($MenuSelection) {
        "1" {
            $SearchTerm = Read-Host "Enter User Name or SAMAccountName (min 2 chars)"
            if ($SearchTerm.Length -lt 2) { 
                Write-Host "Search term must be at least 2 characters." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                continue 
            }
            
            $Filter = "(&(objectCategory=person)(objectClass=user)(|(samaccountname=*$SearchTerm*)(displayname=*$SearchTerm*)(name=*$SearchTerm*)))"
            $Results = Invoke-AdsiQuery -LdapFilter $Filter -Context "User Search: $SearchTerm"
            
            if ($Results) {
                # Display subset in console for readability
                $Results | Select-Object '#', name, samaccountname, mail, enabled, title | Format-Table -AutoSize
                $Results | Out-GridView -Title "User Search Results"
                Show-ResultMenu -DataList $Results -ContextName "UserSearch"
            }
        }
        "2" {
            $SearchTerm = Read-Host "Enter Group Name (min 2 chars)"
            if ($SearchTerm.Length -lt 2) { 
                Write-Host "Search term must be at least 2 characters." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                continue 
            }
            
            $Filter = "(&(objectCategory=group)(|(samaccountname=*$SearchTerm*)(name=*$SearchTerm*)))"
            $Results = Invoke-AdsiQuery -LdapFilter $Filter -Context "Group Search: $SearchTerm"
            
            if ($Results) {
                $Results | Select-Object '#', name, samaccountname, description, groupType | Format-Table -AutoSize
                $Results | Out-GridView -Title "Group Search Results"
                Show-ResultMenu -DataList $Results -ContextName "GroupSearch"
            }
        }
        "3" {
            $SearchTerm = Read-Host "Enter Group Name (min 2 chars)"
            if ($SearchTerm.Length -lt 2) { 
                Write-Host "Search term must be at least 2 characters." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                continue 
            }
            
            # Step 1: Find matching groups
            $GroupFilter = "(&(objectCategory=group)(|(samaccountname=*$SearchTerm*)(name=*$SearchTerm*)))"
            $GroupObjs = Invoke-AdsiQuery -LdapFilter $GroupFilter -Context "Find Group DN"
            
            if (-not $GroupObjs) {
                Write-Host "No groups found matching '$SearchTerm'." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                continue
            }
            
            $SelectedGroup = $null
            
            # If multiple groups are found, utilize the [#] property to let the user pick
            if ($GroupObjs.Count -gt 1) {
                Write-Host "`nMultiple groups found. Please select one:" -ForegroundColor Cyan
                $GroupObjs | Select-Object '#', name, samaccountname, description | Format-Table -AutoSize
                
                $GroupChoice = Read-Host "Enter the [#] of the target group"
                if ($GroupChoice -match '^\d+$') {
                    $SelectedGroup = $GroupObjs | Where-Object { $_.'#' -eq [int]$GroupChoice }
                }
                
                if (-not $SelectedGroup) {
                    Write-Host "Invalid selection. Returning to menu." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                    continue
                }
            } else {
                # Only one group found
                $SelectedGroup = $GroupObjs[0]
            }
            
            # Step 2: Find members of the selected group
            $GroupDN = $SelectedGroup.distinguishedname
            $GroupName = $SelectedGroup.name
            $MemberFilter = "(memberOf=$GroupDN)"
            
            $Results = Invoke-AdsiQuery -LdapFilter $MemberFilter -Context "Group Members of $GroupName"
            
            if ($Results) {
                $Results | Select-Object '#', name, samaccountname, objectClass | Format-Table -AutoSize
                $Results | Out-GridView -Title "Members of $GroupName"
                Show-ResultMenu -DataList $Results -ContextName "GroupMembers"
            } else {
                Write-Host "Group '$GroupName' is empty or members cannot be read." -ForegroundColor Yellow
                Pause
            }
        }
        "4" {
            $CustomFilter = Read-Host "Enter standard LDAP Filter (e.g., (&(objectClass=user)(department=IT*)) )"
            if ([string]::IsNullOrWhiteSpace($CustomFilter)) { continue }
            
            $Results = Invoke-AdsiQuery -LdapFilter $CustomFilter -Context "Custom Query"
            
            if ($Results) {
                # Just show a few common fields in console since query is unknown
                $Results | Select-Object '#', name, samaccountname, objectclass | Format-Table -AutoSize
                $Results | Out-GridView -Title "Custom LDAP Query Results"
                Show-ResultMenu -DataList $Results -ContextName "CustomQuery"
            }
        }
        "Q" {
            Write-Log -Message "User exited the script." -Level INFO
            Write-Host "Exiting script..." -ForegroundColor Green
            $ScriptActive = $false
        }
        default {
            Write-Host "Invalid selection, please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}