<#
.Author
   Cliff Waite
   01/09/2024

.Synopsis
   This script polls AD for all devices and includes information such as Computer Name, Operating System, Operating System Version and Last Logon Timestamp.
   This script is a good addition to pull all machines that are AD registered, current windows versions to detect outdated OS's, and the last time the workstation has communicated with AD. 
   Mostly used when looking to remove devices from AD. 

.EXAMPLE
Computer Name Operating System                Operating System Version Last Logon Timestamp  
------------- ----------------                ------------------------ --------------------  
Device-006      Windows 10 Pro                  10.0 (19042)             12/25/2023 3:23:52 PM 
Device-020      Windows 10 Pro                  10.0 (19042)             12/25/2023 11:21:56 PM
Device-023      Windows 10 Pro                  10.0 (19042)             12/26/2023 6:39:51 AM 
Device-012      Windows 10 Pro                  10.0 (19042)             12/26/2023 7:22:17 AM 
Device-002      Windows 10 Pro                  10.0 (19041)             12/26/2023 8:25:01 PM 
Device-008      Windows 10 Pro                  10.0 (19042)             12/28/2023 6:00:22 AM 
Device-024      Windows 10 Pro                  10.0 (19043)             12/28/2023 7:39:54 AM 
Device-013      Windows 10 Pro                  10.0 (19044)             12/28/2023 11:59:09 AM
Device-007      Windows 10 Pro                  10.0 (19042)             12/28/2023 3:33:53 PM 
Device-003      Windows 10 Pro                  10.0 (17134)             12/30/2023 8:41:08 PM 
Device-DC0      Windows Server 2012 R2 Standard 6.3 (9600)               12/30/2023 11:31:48 PM

#>
# Import the Active Directory module
Import-Module ActiveDirectory

# Get all computers from Active Directory
$computers = Get-ADComputer -Filter * -Properties * | Where-Object { $_.Enabled -eq $True }

# Create an array to store computer information
$computerInfo = @()

# Iterate through each computer and add information to the array
foreach ($computer in $computers) {
    $computerName = $computer.Name
    $operatingSystem = $computer.OperatingSystem
    $operatingSystemVersion = $computer.OperatingSystemVersion
    $lastLogonTimestamp = $computer.lastLogonTimestamp

    # Convert the timestamp to a DateTime object
    $lastLogonDateTime = [DateTime]::FromFileTime($lastLogonTimestamp)

    $computerInfo += [PSCustomObject]@{
        'Computer Name'           = $computerName
        'Operating System'        = $operatingSystem
        'Operating System Version' = $operatingSystemVersion
        'Last Logon Timestamp'    = $lastLogonDateTime  

    }
}
# Sort the array by Last Logon Timestamp in ascending order
$computerInfo = $computerInfo | Sort-Object 'Last Logon Timestamp'

# Display the information as a table
$computerInfo | Format-Table -AutoSize 