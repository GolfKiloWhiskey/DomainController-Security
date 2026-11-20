<# 
.NOTES 
Author: Cliff Waite 
Date: 13/03/2026
Email: cliff.ps@nutmegtech.com
Version: 1.0

.SYNOPSIS 
Modernized AD Group Member retrieval with menu-driven interface and CSV export.

VERSIONING 
1.0 - Initial release with modern Get-ADObject pipeline and menu system.
#>

$ScriptVersion = "1.0"
$DefaultExportPath = "C:\Temp\DomainAdmins_Members.csv"

# --- MODULE CHECK ---
if (-not (Get-Module -ListAvailable ActiveDirectory)) {
    Write-Host "ActiveDirectory module not found. Attempting install..." -ForegroundColor Yellow
    Install-WindowsFeature RSAT-AD-PowerShell -ErrorAction SilentlyContinue
}

# --- MENU INTERFACE ---
function Show-Menu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   AD GROUP AUDIT TOOL (MODERN)      " -ForegroundColor Yellow
    Write-Host "   Author: Cliff Waite                       " -ForegroundColor DarkGray
    Write-Host "   Email: cliff.ps@nutmegtech.com            " -ForegroundColor DarkGray
    Write-Host "   Version: $ScriptVersion                   " -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "1. View Domain Admins (Display Only)"
    Write-Host "2. Export Domain Admins to CSV ($DefaultExportPath)"
    Write-Host "3. Audit specific Group (Manual Entry)"
    Write-Host "Q. Quit"
    Write-Host "---------------------------------------------"
}

# --- CORE LOGIC ---
function Get-ModernGroupMembers {
    param([string]$GroupName)

    try {
        # Efficient retrieval using DistinguishedName pipeline
        $Group = Get-ADGroup -Identity $GroupName -Properties Member
        if ($Group.Member.Count -gt 0) {
            $Results = $Group.Member | Get-ADObject -Properties DisplayName, SamAccountName, LastLogonDate, EmailAddress | Select-Object `
                @{Name="Group"; Expression={$GroupName}},
                Name, 
                SamAccountName, 
                @{Name="Type"; Expression={$_.ObjectClass}}, 
                LastLogonDate, 
                EmailAddress
            return $Results
        } else {
            Write-Host "No members found in $GroupName." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Error retrieving group '$GroupName': $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- MAIN LOOP ---
do {
    Show-Menu
    $Choice = Read-Host "Select an option"

    switch ($Choice) {
        "1" {
            $Data = Get-ModernGroupMembers -GroupName "Domain Admins"
            $Data | Format-Table -AutoSize
            Read-Host "`nPress Enter to return to menu"
        }
        "2" {
            if (-not (Test-Path "C:\Temp")) { New-Item -Path "C:\Temp" -ItemType Directory | Out-Null }
            $Data = Get-ModernGroupMembers -GroupName "Domain Admins"
            $Data | Export-Csv -Path $DefaultExportPath -NoTypeInformation
            Write-Host "Export successful: $DefaultExportPath" -ForegroundColor Green
            Read-Host "`nPress Enter to return to menu"
        }
        "3" {
            $CustomGroup = Read-Host "Enter the name of the AD Group"
            $Data = Get-ModernGroupMembers -GroupName $CustomGroup
            $Data | Format-Table -AutoSize
            Read-Host "`nPress Enter to return to menu"
        }
    }
} while ($Choice -ne "Q")