# This script creates folders based on the sAMAccountName attribute in a folder you specifiy in a variable. Edit the variables below

# Replace the following variables with your actual values
# $TargetFolder is where you want to create the folders (Can be a netowrk location, but you must use the hidden share name of the drive, such as \\FS01\e$\shares, or if locally, just supply the local path to the folder. C:\Shares
# $domaincontroller is the DC you want to target for user info
# $domainname is part of the disinguished name such as DC=domain,DC=local (only need the domain part)
# $Suffix is part of the distinguishedname as well, (Suffix is .local, .com, etc.
# $ouName is the OU you want to target where you users live. Such as "OU=Users,DC=domain,DC=local"

$targetFolder = ""
$domainController = ""
$domainName = ""
$domainsuffix = ""
$ouName = ""

# Check if the ActiveDirectory module is installed, and install it if not found
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "Installing ActiveDirectory module..."
    Install-Module -Name ActiveDirectory -Force
}

# Connect to the Active Directory server
Import-Module ActiveDirectory

# Get users from the specified OU
$users = Get-ADUser -Filter * -Server $domainController -SearchBase $ouName -Properties SamAccountName

# Create folders for each user
foreach ($user in $users) {
    $samAccountName = $user.SamAccountName
    $userFolder = Join-Path -Path $targetFolder -ChildPath $samAccountName

    # Check if the folder already exists
    if (-Not (Test-Path $userFolder -PathType Container)) {
        try {
            New-Item -Path $userFolder -ItemType Directory -ErrorAction Stop
            Write-Host "Folder created for $samAccountName"
        } catch {
            #Write-Host "Error creating folder for $samAccountName: $_.Exception.Message"
        }
    } else {
        Write-Host "Folder already exists for $samAccountName"
    }
}