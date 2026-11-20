<# 
.NOTES 
Author: Cliff Waite 
Date: 11/02/2026
Email: cliff.ps@nutmegtech.com
Version: 2.0

.SYNOPSIS 
Imports a CSV (First Name, Last Name, ID) and merges the ID into the employeeID attribute in AD.
Features a 5-tier matching system, Gap Analysis, and a "Smart Split" Manual Resolver for compound surnames.

VERSIONING 
2.0 - Major update to Manual Resolver. Now splits compound CSV surnames (spaces or hyphens) and searches AD for EACH part individually if the full match fails.
1.9 - Fixed GUID casting error.
#>

# Requires PowerShell 7, compatible with 5.0
#Requires -Version 5.0

# --- MODULE CHECK ---
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Warning "ActiveDirectory module is missing."
}
if (-not (Get-Module -Name ActiveDirectory)) {
    Import-Module ActiveDirectory
}

$ScriptVersion = "2.0"

function Show-Menu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   AD USER ID MERGE UTILITY      " -ForegroundColor Yellow
    Write-Host "   Author: Cliff Waite                       " -ForegroundColor DarkGray
    Write-Host "   Email:cliff.ps@nutmegtech.com             " -ForegroundColor DarkGray
    Write-Host "   Version: $ScriptVersion                   " -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "1. Run Simulation (Dry Run - No Changes)" -ForegroundColor Green
    Write-Host "2. Run Live Import (Writes to AD)" -ForegroundColor Red
    Write-Host "Q. Quit" -ForegroundColor White
    Write-Host "=============================================" -ForegroundColor Cyan
}

# --- LOGIC ---
do {
    Show-Menu
    $Choice = Read-Host "Select an option"

    if ($Choice -in '1', '2') {
        $Simulate = if ($Choice -eq '1') { $true } else { $false }
        
        # Safety Check for Live Mode
        if (-not $Simulate) {
            Write-Host "WARNING: You have selected LIVE mode." -ForegroundColor Red
            $Confirm = Read-Host "Are you sure you want to write changes to AD? (Y/N)"
            if ($Confirm -ne 'Y') { continue }
        }

        # Get CSV Path
        $DefaultPath = "C:\Temp\Users.csv"
        $CsvPath = Read-Host "Enter path to CSV file (Default: $DefaultPath)"
        if ([string]::IsNullOrWhiteSpace($CsvPath)) { $CsvPath = $DefaultPath }

        if (-not (Test-Path $CsvPath)) {
            Write-Warning "File not found at $CsvPath!"
            Pause
            continue
        }

        # Import Data
        try {
            $CsvData = Import-Csv $CsvPath
        }
        catch {
            Write-Error "Failed to read CSV. Ensure headers are 'First Name', 'Last Name', and 'ID'."
            Pause
            continue
        }

        # Validate Headers
        $Headers = $CsvData[0].PSObject.Properties.Name
        if ($Headers -notcontains "First Name" -or $Headers -notcontains "Last Name" -or $Headers -notcontains "ID") {
            Write-Warning "CSV headers mismatch! Found: $($Headers -join ', ')"
            Write-Warning "Expected: 'First Name', 'Last Name', 'ID'"
            Pause
            continue
        }

        # TRACKING COLLECTIONS
        $MatchedADGuids = New-Object System.Collections.Generic.HashSet[Guid]
        $UnmatchedCSVRows = New-Object System.Collections.Generic.List[PSObject]
        $SuccessfulMatches = New-Object System.Collections.Generic.List[PSObject]

        # --- PROCESS LOOP ---
        foreach ($Row in $CsvData) {
            # Input Cleaning
            $FirstName = $Row."First Name".Trim()
            $LastName = $Row."Last Name".Trim()
            $NewID = $Row.ID.Trim()
            
            # Sanitization (Apostrophes)
            $SafeFirst = $FirstName -replace "'", "''"
            $SafeLast  = $LastName -replace "'", "''"
            $SafeFull  = "$SafeFirst $SafeLast"

            $ADUser = $null
            $MatchMethod = "None"
            
            Write-Host "`n--------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "Processing: $FirstName $LastName (ID: $NewID)..." -NoNewline

            # --- AUTOMATED MATCHING ---

            # 1. Exact Match
            if (-not $ADUser) {
                try {
                    $ADUser = Get-ADUser -Filter "GivenName -eq '$SafeFirst' -and Surname -eq '$SafeLast'" -Properties employeeID, ObjectGUID -ErrorAction SilentlyContinue
                    if ($ADUser) { $MatchMethod = "Exact Match" }
                } catch {}
            }

            # 2. Fuzzy Match (Surname + 3 chars)
            if (-not $ADUser -and $FirstName.Length -ge 3) {
                $ShortFirst = $SafeFirst.Substring(0, 3)
                try {
                    $PotentialMatches = Get-ADUser -Filter "Surname -eq '$SafeLast' -and GivenName -like '$ShortFirst*'" -Properties employeeID, ObjectGUID -ErrorAction SilentlyContinue
                    if ($PotentialMatches.Count -eq 1) {
                        $ADUser = $PotentialMatches
                        $MatchMethod = "Fuzzy Match (3-Char)"
                    }
                } catch {}
            }

            # 3. ANR Fallback
            if (-not $ADUser) {
                try {
                    $PotentialMatches = Get-ADUser -Filter "anr -eq '$SafeFull'" -Properties employeeID, ObjectGUID -ErrorAction SilentlyContinue
                    if ($PotentialMatches.Count -eq 1) {
                        $ADUser = $PotentialMatches
                        $MatchMethod = "ANR Fallback"
                    }
                } catch {}
            }

            # 4. Auto Compound Surname Logic
            if (-not $ADUser -and $LastName -match '[ -]') {
                $Parts = $LastName -split '[ -]'
                $Part1 = $Parts[0] -replace "'", "''"
                
                try {
                    $PotentialMatches = Get-ADUser -Filter "GivenName -eq '$SafeFirst' -and Surname -eq '$Part1'" -Properties employeeID, ObjectGUID -ErrorAction SilentlyContinue
                    if ($PotentialMatches.Count -eq 1) {
                        $ADUser = $PotentialMatches
                        $MatchMethod = "Compound Surname Match (Part 1)"
                    }
                } catch {}
            }

            # --- MANUAL RESOLVER ---
            if (-not $ADUser) {
                Write-Host " [NO AUTO-MATCH]" -ForegroundColor Yellow
                
                $Candidates = @()
                
                # A. Initial Search (Broadest Safe Search)
                $FirstInitial = $SafeFirst.Substring(0,1)
                try { 
                    $Found = Get-ADUser -Filter "Surname -eq '$SafeLast' -and GivenName -like '$FirstInitial*'" -Properties employeeID, UserPrincipalName, ObjectGUID -ErrorAction SilentlyContinue
                    $Candidates += $Found
                } catch {}

                # B. Surname Only Fallback (Smart Split)
                if ($Candidates.Count -eq 0) {
                     # 1. Try EXACT CSV Surname first
                     try { 
                        $Found = Get-ADUser -Filter "Surname -eq '$SafeLast'" -Properties employeeID, UserPrincipalName, ObjectGUID -ResultSetSize 10 -ErrorAction SilentlyContinue
                        $Candidates += $Found
                     } catch {}

                     # 2. If CSV Surname is compound (Space or Hyphen), try EACH part individually
                     if ($Candidates.Count -eq 0 -and $LastName -match '[ -]') {
                        $Parts = $LastName -split '[ -]'
                        Write-Host "    Splitting Surname '$LastName' to find matches..." -ForegroundColor DarkGray
                        
                        foreach ($Part in $Parts) {
                            if ($Part.Length -gt 2) { # Skip short bits like "De" or "La" if you want, or keep them
                                $SafePart = $Part -replace "'", "''"
                                try {
                                    $Found = Get-ADUser -Filter "Surname -eq '$SafePart'" -Properties employeeID, UserPrincipalName, ObjectGUID -ResultSetSize 5 -ErrorAction SilentlyContinue
                                    # Avoid duplicates if multiple parts return same user
                                    foreach ($F in $Found) {
                                        # Custom logic to check if already in candidates
                                        $AlreadyExists = $false
                                        foreach ($C in $Candidates) { if ($C.ObjectGUID -eq $F.ObjectGUID) { $AlreadyExists = $true } }
                                        if (-not $AlreadyExists) { $Candidates += $F }
                                    }
                                } catch {}
                            }
                        }
                     }
                }

                if ($Candidates.Count -gt 0) {
                    Write-Host "    Found $($Candidates.Count) possible matches:" -ForegroundColor Cyan
                    for ($i = 0; $i -lt $Candidates.Count; $i++) {
                        $C = $Candidates[$i]
                        Write-Host "    [$($i+1)] Name: $($C.Name) | UPN: $($C.UserPrincipalName) | CurrID: $($C.employeeID)"
                    }
                    
                    $Selection = Read-Host "    Select match number (0 to Skip)"
                    if ($Selection -match "^\d+$" -and $Selection -gt 0 -and $Selection -le $Candidates.Count) {
                        $ADUser = $Candidates[$Selection - 1]
                        $MatchMethod = "Manual Selection"
                    }
                }
            }

            # --- ACTION & TRACKING ---
            if ($ADUser) {
                try {
                    $MatchedADGuids.Add([Guid]$ADUser.ObjectGUID) | Out-Null
                } catch {
                     Write-Warning "Could not track GUID for $($ADUser.Name)."
                }

                $ActionStatus = ""
                
                Write-Host " -> Selected: $($ADUser.Name) [$MatchMethod]" -ForegroundColor Green
                
                if ($ADUser.employeeID -eq $NewID) {
                     Write-Host "    - ID already matches ($NewID). No action needed." -ForegroundColor Gray
                     $ActionStatus = "Skipped (Already Matched)"
                }
                else {
                    if ($Simulate) {
                        Write-Host "    - [DRY RUN] Would change ID from '$($ADUser.employeeID)' to '$NewID'" -ForegroundColor Cyan
                        $ActionStatus = "Simulated Update"
                    }
                    else {
                        try {
                            Set-ADUser -Identity $ADUser.DistinguishedName -EmployeeID $NewID -ErrorAction Stop
                            Write-Host "    - [SUCCESS] Updated EmployeeID to $NewID" -ForegroundColor Green
                            $ActionStatus = "Updated Success"
                        }
                        catch {
                            Write-Host "    - [ERROR] Failed to update: $($_.Exception.Message)" -ForegroundColor Red
                            $ActionStatus = "Update Failed"
                        }
                    }
                }

                $SuccessfulMatches.Add([PSCustomObject]@{
                    Name   = $ADUser.Name
                    ID     = $NewID
                    Status = $ActionStatus
                })
            }
            else {
                Write-Host "    No match found. Added to Gap Report." -ForegroundColor Red
                $UnmatchedCSVRows.Add($Row)
            }
        }
        
        # --- GAP ANALYSIS & EXPORT SECTION ---
        Clear-Host
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host "           GAP ANALYSIS REPORT               " -ForegroundColor Yellow
        Write-Host "=============================================" -ForegroundColor Cyan
        
        $CountCSV = $UnmatchedCSVRows.Count
        Write-Host "1. CSV Rows NOT found in AD: $CountCSV" -ForegroundColor $(if($CountCSV -gt 0){'Red'}else{'Green'})
        
        if ($CountCSV -gt 0) {
            Write-Host "   (Example: $($UnmatchedCSVRows[0].'First Name') $($UnmatchedCSVRows[0].'Last Name'))" -ForegroundColor DarkGray
        }

        Write-Host "`n2. AD Users NOT in CSV (Gap Check)"
        $RunGapCheck = Read-Host "   Do you want to scan AD for users missing from this CSV? (Y/N)"
        
        $MissingADUsers = @()
        if ($RunGapCheck -eq 'Y') {
            Write-Host "   Scanning Active Directory (Enabled Users)..." -ForegroundColor Cyan
            $AllAD = Get-ADUser -Filter "Enabled -eq 'True' -and Surname -like '*'" -Properties employeeID, ObjectGUID
            
            foreach ($User in $AllAD) {
                if (-not $MatchedADGuids.Contains([Guid]$User.ObjectGUID)) {
                    $MissingADUsers += $User
                }
            }
            Write-Host "   Found $($MissingADUsers.Count) users in AD that were NOT in your CSV." -ForegroundColor Yellow
        }

        if ($UnmatchedCSVRows.Count -gt 0 -or $MissingADUsers.Count -gt 0) {
            Write-Host "`n---------------------------------------------"
            $Export = Read-Host "Would you like to export these lists to CSV? (Y/N)"
            
            if ($Export -eq 'Y') {
                $TimeStamp = Get-Date -Format "yyyyMMdd-HHmm"
                
                if ($UnmatchedCSVRows.Count -gt 0) {
                    $Path1 = "C:\Temp\GapReport_NotInAD_$TimeStamp.csv"
                    $UnmatchedCSVRows | Export-Csv -Path $Path1 -NoTypeInformation
                    Write-Host "   Exported CSV Orphans to: $Path1" -ForegroundColor Green
                }
                
                if ($MissingADUsers.Count -gt 0) {
                    $Path2 = "C:\Temp\GapReport_NotInCSV_$TimeStamp.csv"
                    $MissingADUsers | Select-Object Name, UserPrincipalName, EmployeeID, Enabled | Export-Csv -Path $Path2 -NoTypeInformation
                    Write-Host "   Exported AD Orphans to:  $Path2" -ForegroundColor Green
                }
            }
        }

        # --- FINAL CONSOLE REPORTING ---
        Write-Host "`n=============================================" -ForegroundColor Cyan
        Write-Host "        FINAL CONSOLE REPORT                 " -ForegroundColor Yellow
        Write-Host "=============================================" -ForegroundColor Cyan
        
        if ($SuccessfulMatches.Count -gt 0) {
            Write-Host "`n--- SUCCESSFULLY MATCHED USERS (A-Z) ---" -ForegroundColor Green
            $SortedMatches = $SuccessfulMatches | Sort-Object Name
            
            foreach ($Match in $SortedMatches) {
                $Color = if ($Match.Status -like "*Failed*") { "Red" } 
                         elseif ($Match.Status -like "*Skipped*") { "Gray" } 
                         else { "Green" }
                         
                Write-Host "$($Match.Name) `t- ID: $($Match.ID) `t[$($Match.Status)]" -ForegroundColor $Color
            }
        }

        if ($UnmatchedCSVRows.Count -gt 0) {
            Write-Host "`n---------------------------------------------"
            $ShowUnmatched = Read-Host "Would you like to see the UNMATCHED names on console? (Y/N)"
            if ($ShowUnmatched -eq 'Y') {
                Write-Host "`n--- UNMATCHED USERS (FROM CSV) ---" -ForegroundColor Red
                foreach ($Row in $UnmatchedCSVRows) {
                    Write-Host "$($Row."First Name") $($Row."Last Name") (ID: $($Row.ID))" -ForegroundColor Red
                }
            }
        }

        Write-Host "`nRun Complete." -ForegroundColor Yellow
        Pause
    }
    elseif ($Choice -in 'Q', 'q') {
        Write-Host "Exiting..." -ForegroundColor Cyan
    }

} until ($Choice -in 'Q', 'q')