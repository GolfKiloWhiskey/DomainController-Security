<#
.Author
   Cliff Waite
   01/09/2024

.Synopsis
   This script polls AD for all user accounts in a desingated serachbase (OU) and shows the Display Name, PasswordLastSet and Account Enabled values. 
   This script is used mostly when trying to find old or outdated users, termed users or current users who have not reset their password recently. 
   Script outputs to a CSV (Check Line 43 and set your desired output folder/file name) and sorts it by the PasswordLastSet column from oldest to newest. 
   

.EXAMPLE
CSV Export:
DisplayName	             PasswordLastSet	 Enabled
QBDataServiceUser17	      7/15/2009 13:12	 TRUE
QBDataServiceUser19	      7/20/2009 12:48	 TRUE
QBDataServiceUser21	      11/24/2010 9:42	 TRUE
QBDataServiceUser22	      5/17/2012 10:37	 TRUE
Integration Svc	      11/1/2012 11:51	 TRUE
PatchAdmin	          1/27/2014 10:01	 FALSE
FSAdmin	      1/27/2014 10:14	 FALSE
QBDataServiceUser23	      5/7/2014 8:32	     TRUE

#>

# SearchBase configuration. Enter the distnguished name of the OU you'd like to search within, Example: "OU=users,DC=server,DC=local"
param (
    [string]$OU = ""
)

# Import the Active Directory module
Import-Module ActiveDirectory

# Specify the search base using the distinguished name (DN) of the OU
$searchBase = "$OU"

# Get all users and their last password set date, enabled status, and password expired status
$users = Get-ADUser -Filter * -SearchBase $searchBase -Properties DisplayName, PasswordLastSet, Enabled, "msDS-UserPasswordExpiryTimeComputed"

# Sort the users by the last password set date
$users = $users | Sort-Object PasswordLastSet

# Define the path to the CSV file
$csvPath = "C:\temp\ADUsers_LastLogon.csv"

# Export the information to a CSV file
$users | Select-Object DisplayName, Enabled, @{Name='PasswordLastSet'; Expression={Get-Date $_.PasswordLastSet -Format 'yyyy-MM-dd HH:mm:ss'}}, @{Name='PasswordExpired'; Expression={($_.'msDS-UserPasswordExpiryTimeComputed' -ne 0) -and (Get-Date $_.'msDS-UserPasswordExpiryTimeComputed' -lt (Get-Date))}} | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host "Export completed. AD users with last logon date exported to: $csvPath"
