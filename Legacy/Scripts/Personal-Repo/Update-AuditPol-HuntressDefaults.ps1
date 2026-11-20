<# 
.NOTES 
Author: Cliff Waite 
Date: 13/05/2026
Email: cliff.ps@nutmegtech.com
Version: 2.0

.SYNOPSIS 
Menu-driven script to verify and apply Advanced Audit Policy settings using auditpol.exe based on Huntress recommendations.

VERSIONING 
2.0 - Expanded and updated entire policy array to match Huntress comprehensive EDR recommendations.
1.1 - Corrected subcategory name for PNP Activity to Plug and Play Events; suppressed stderr bleeding.
1.0 - Initial script creation.
#>

$ScriptVersion = "2.0"

# Define the target audit policy settings based on Huntress recommendations
# Note: "PNP Activity" translates to "Plug and Play Events" in auditpol
# Note: "Audit User/Device Claims" translates to "User / Device Claims" in auditpol
$Policies = @(
    # Account Logon
    [PSCustomObject]@{ Subcategory = "Credential Validation"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Kerberos Authentication Service"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Kerberos Service Ticket Operations"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Other Account Logon Events"; Success = "disable"; Failure = "disable" }
    
    # Account Management
    [PSCustomObject]@{ Subcategory = "Application Group Management"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Computer Account Management"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Distribution Group Management"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Other Account Management Events"; Success = "enable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Security Group Management"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "User Account Management"; Success = "enable"; Failure = "enable" }
    
    # Detailed Tracking
    [PSCustomObject]@{ Subcategory = "DPAPI Activity"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Plug and Play Events"; Success = "enable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Process Creation"; Success = "disable"; Failure = "disable" } # Huntress handles via EDR
    [PSCustomObject]@{ Subcategory = "Process Termination"; Success = "disable"; Failure = "disable" } # Huntress handles via EDR
    [PSCustomObject]@{ Subcategory = "RPC Events"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Token Right Adjustment Events"; Success = "disable"; Failure = "disable" }
    
    # DS Access
    [PSCustomObject]@{ Subcategory = "Detailed Directory Service Replication"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Directory Service Access"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Directory Service Changes"; Success = "enable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Directory Service Replication"; Success = "disable"; Failure = "disable" }
    
    # Logon/Logoff
    [PSCustomObject]@{ Subcategory = "Account Lockout"; Success = "disable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "User / Device Claims"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Group Membership"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "IPsec Extended Mode"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "IPsec Main Mode"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "IPsec Quick Mode"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Logoff"; Success = "enable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Logon"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Network Policy Server"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Other Logon/Logoff Events"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Special Logon"; Success = "enable"; Failure = "disable" }
    
    # Object Access
    [PSCustomObject]@{ Subcategory = "Application Generated"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Certification Services"; Success = "disable"; Failure = "disable" } # Enable if using MS Cert Services
    [PSCustomObject]@{ Subcategory = "Detailed File Share"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "File Share"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "File System"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Filtering Platform Connection"; Success = "disable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Filtering Platform Packet Drop"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Handle Manipulation"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Kernel Object"; Success = "enable"; Failure = "enable" } # Needs "Audit access of global system objects" disabled
    [PSCustomObject]@{ Subcategory = "Other Object Access Events"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Registry"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Removable Storage"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "SAM"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Central Access Policy Staging"; Success = "disable"; Failure = "disable" }
    
    # Policy Change
    [PSCustomObject]@{ Subcategory = "Audit Policy Change"; Success = "enable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Authentication Policy Change"; Success = "enable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Authorization Policy Change"; Success = "enable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Filtering Platform Policy Change"; Success = "enable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "MPSSVC Rule-Level Policy Change"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Other Policy Change Events"; Success = "enable"; Failure = "enable" }
    
    # Privilege Use
    [PSCustomObject]@{ Subcategory = "Non Sensitive Privilege Use"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Other Privilege Use Events"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Sensitive Privilege Use"; Success = "enable"; Failure = "enable" }
    
    # System
    [PSCustomObject]@{ Subcategory = "IPsec Driver"; Success = "disable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Other System Events"; Success = "enable"; Failure = "enable" }
    [PSCustomObject]@{ Subcategory = "Security State Change"; Success = "enable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "Security System Extension"; Success = "enable"; Failure = "disable" }
    [PSCustomObject]@{ Subcategory = "System Integrity"; Success = "enable"; Failure = "enable" }
)

Function Verify-AuditStatus {
    Write-Host "`nVerifying Current Audit Policies against Huntress state..." -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
    foreach ($Policy in $Policies) {
        # Fetch current status. Redirecting stderr (2>$null) prevents unsupported OS subcategories from bleeding into the console.
        $auditData = auditpol /get /subcategory:"$($Policy.Subcategory)" /r 2>$null | ConvertFrom-Csv -ErrorAction SilentlyContinue

        if ($auditData) {
            $currentSetting = $auditData.'Inclusion Setting'
        } else {
            $currentSetting = "Unknown/Not Supported"
        }

        # Determine expected string based on our target configuration
        $expected = ""
        if ($Policy.Success -eq "enable" -and $Policy.Failure -eq "enable") { 
            $expected = "Success and Failure" 
        } elseif ($Policy.Success -eq "enable") { 
            $expected = "Success" 
        } elseif ($Policy.Failure -eq "enable") { 
            $expected = "Failure" 
        } else { 
            $expected = "No Auditing" 
        }

        # Compare and output
        if ($currentSetting -match $expected) {
            Write-Host "[MATCH]" -ForegroundColor Green -NoNewline
            Write-Host " $($Policy.Subcategory): $currentSetting"
        } else {
            Write-Host "[MISMATCH]" -ForegroundColor Red -NoNewline
            Write-Host " $($Policy.Subcategory) - " -NoNewline
            Write-Host "Current: '$currentSetting' | Expected: '$expected'" -ForegroundColor Yellow
        }
    }
    Write-Host "`nVerification complete." -ForegroundColor Cyan
    Pause
}

Function Update-AuditPolicies {
    Write-Host "`nApplying target Audit Policies from Huntress..." -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
    foreach ($Policy in $Policies) {
        Write-Host "Configuring $($Policy.Subcategory)... " -NoNewline
        
        # Execute auditpol set command
        $cmdOutput = auditpol /set /subcategory:"$($Policy.Subcategory)" /success:$($Policy.Success) /failure:$($Policy.Failure) 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Success" -ForegroundColor Green
        } else {
            Write-Host "Failed" -ForegroundColor Red
            # Catch common error codes to provide readable output
            if ($cmdOutput -match "0x00000057") {
                Write-Host "  Error: Subcategory not recognized or not supported on this OS version." -ForegroundColor DarkRed
            } else {
                Write-Host "  Error: $cmdOutput" -ForegroundColor DarkRed
            }
        }
    }
    Write-Host "`nPolicy update process complete." -ForegroundColor Cyan
    Pause
}

# --- MAIN MENU LOOP ---
while ($true) {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   ADVANCED AUDIT POLICY MANAGER (HUNTRESS)  " -ForegroundColor Yellow
    Write-Host "   Author: Cliff Waite                       " -ForegroundColor DarkGray
    Write-Host "   Email:cliff.ps@nutmegtech.com             " -ForegroundColor DarkGray
    Write-Host "   Version: $ScriptVersion                   " -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    
    Write-Host "`nPlease select an option:"
    Write-Host "1. Verify Audit Policy Status"
    Write-Host "2. Update Audit Policies"
    Write-Host "3. Exit`n"

    $Choice = Read-Host "Enter your selection (1-3)"

    switch ($Choice) {
        '1' { Verify-AuditStatus }
        '2' { Update-AuditPolicies }
        '3' { 
            Write-Host "Exiting script..." -ForegroundColor Yellow
            break 
        }
        default { 
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}