<#
.Author
   Cliff Waite
   Nutmeg Technologies
   11/13/2023
.Synopsis
   This script provides functionality to either update or remove the Connect/Home Folder attributes for a user's AD profile. Edit the variables below to the correct domain structure.  
   To remove all Connect/Home Folder Attributes, leave all variables alone EXCEPT change "$clearHomeDrive = $false" to "$True". This will remove the attributes. 
   Keep the variable configured as $false to add Connect/Home Folder attributes (but edit the apprprate variables to do so!)
   MUST BE RUN AS ADMIN. 
#>

# Specify the target OU
$ouPath = "OU=Users,DC=contoso,DC=com"

# Specify the new home drive letter
$newHomeDriveLetter = "U:"

# Specify the server and share for the home folder
$homeFolderServer = "ServerName"
$homeFolderShare = "Share"

# Specify whether to update or clear the home drive attribute
$clearHomeDrive = $true

# Get all user accounts from the specified OU
$users = Get-ADUser -Filter * -SearchBase $ouPath

foreach ($user in $users) {
    if ($clearHomeDrive) {
        # Clear the home drive letter and path for the user
        Set-ADUser -Identity $user.SamAccountName -HomeDrive $null -HomeDirectory $null

        # Display a message for each user
        Write-Host "Cleared home drive for $($user.SamAccountName)"
    }
    else {
        # Construct the new home folder connect path for each user
        $newHomePath = Join-Path $homeFolderServer ($homeFolderShare + "\" + $user.SamAccountName)

        # Update the home drive letter and path for the user
        Set-ADUser -Identity $user.SamAccountName -HomeDrive $newHomeDriveLetter -HomeDirectory $newHomePath

        # Display a message for each user
        Write-Host "Updated home drive for $($user.SamAccountName) to $($newHomeDriveLetter)$newHomePath"
    }
}