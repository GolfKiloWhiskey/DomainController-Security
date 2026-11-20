# Split path
$Path = Split-Path -Parent "C:\Temp\*.*"

# Create variable for the date stamp in log file
$LogDate = Get-Date -f yyyyMMddhhmm

# Define CSV and log file location variables
# They have to be on the same location as the script
$Csvfile = $Path + "\AllActiveADUsers_$logDate.csv"

# Import Active Directory module
Import-Module ActiveDirectory

# Create empty array
$AllActiveADUsers = @()

# Loop through every DN
$AllActiveADUsers += $(Get-ADUser -Filter 'enabled -eq $true' -Properties *)

# Create list
$AllActiveADUsers | Sort-Object Name | Select-Object `
@{Label = "First name"; Expression = { $_.GivenName } },
@{Label = "Last name"; Expression = { $_.Surname } },
@{Label = "Display name"; Expression = { $_.DisplayName } },
@{Label = "User logon name"; Expression = { $_.SamAccountName } }|

# Export report to CSV file
Export-Csv -Encoding UTF8 -Path $Csvfile -NoTypeInformation #-Delimiter ";"