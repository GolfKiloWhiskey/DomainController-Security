#Import the ActiveDirectory Module 
Import-Module ActiveDirectory

#Get System Info
$sysinfo = Get-WmiObject -Class Win32_ComputerSystem

#Insert the old UPN Suffix here 
$server = “{0}.{1}” -f $sysinfo.Name, $sysinfo.Domain
$oldSuffix = $sysinfo.Domain

#Insert the new UPN Suffix here  
$newSuffix = Get-adforest | select UPNSuffixes -ExpandProperty UPNSuffixes

#Replace with the OU you want to change suffixes for 
$ou = ""

#Replace with the name of one of your AD server's
$LocalServerFQDN = (Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain

#Now the script to replace the user accounts
Get-ADUser -SearchBase $ou -filter * | ForEach-Object { 
$newUpn = $_.UserPrincipalName.Replace($oldSuffix,$newSuffix) 
$_ | Set-ADUser -server $LocalServerFQDN -UserPrincipalName $newUpn 
}