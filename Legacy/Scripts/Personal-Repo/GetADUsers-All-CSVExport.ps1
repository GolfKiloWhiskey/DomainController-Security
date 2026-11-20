<#
.NOTES
    Author: Cliff Waite
    Date: 2024-07-19
    Email: cliff.ps@nutmegtech.com
    Version: 1.1

.SYNOPSIS
    This script retrieves all Active Directory users with specific properties and exports the results to a CSV file.

.DESCRIPTION
    The script fetches all Active Directory users and displays the following properties:
    - Enabled
    - PasswordExpired
    - PasswordLastSet
    - PasswordNeverExpires
    - PasswordNotRequired
    - Name
    - SamAccountName
    - EmailAddress
    - proxyAddresses
    - LockedOut
    - AccountExpirationDate
    - LastLogonDate
    - LastLogon (converted to readable format)
    - DistinguishedName

    The results are then exported to a CSV file.

.EXAMPLE
    To run the script, execute the following command in PowerShell:

    .\Get-ADUsers.ps1 -OutputPath "C:\Path\To\Output.csv"
#>


param (
    [string]$OutputPath = "ADUsers.csv"
)

# Function to convert LastLogon timestamp to a readable format
function LastLogonConvert {
    param (
        [datetime]$lastLogonTimestamp
    )
    return $lastLogonTimestamp.ToLocalTime()
}

# Import Active Directory module
Import-Module ActiveDirectory

# Get all AD users with specified properties
$adUsers = Get-ADUser -Filter * -Property  Name, SamAccountName, Enabled, LastLogonDate, LastLogon, PasswordExpired, PasswordLastSet, PasswordNeverExpires, PasswordNotRequired, EmailAddress, proxyAddresses, LockedOut, AccountExpirationDate, DistinguishedName | Select-Object Enabled, PasswordExpired, PasswordLastSet, PasswordNeverExpires, PasswordNotRequired, Name, SamAccountName, EmailAddress, proxyAddresses, LockedOut, AccountExpirationDate, LastLogonDate, @{ Name = 'lastlogon'; Expression = { LastLogonConvert $_.LastLogon } }, DistinguishedName

# Export the results to CSV
$adUsers | Export-Csv -Path "C:\Temp\$outputpath" -NoTypeInformation

Write-Host "Export completed. CSV file saved to $OutputPath"