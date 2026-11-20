#NOT COMPLETE. MUST EDIT "Get-ADUSER" construct.
#01/24/2024

<#
.Author
   Cliff Waite
   01/09/2024

.Synopsis
   This script polls AD for all enabled AD users which have the "Password Never Expires" attirbute flag, then subsequently removes the flag for the detected users, changes the account password to a pre-defind password and sets the accounts to "User must change password at next logon"
   This script is used primarily when doing org wide password changes. 
   NOTE: Be mindful of what you set as your target OU. If you use the top level domain, ALL ACCOUNTS ARE SUBJECT TO PASSWORD EXPIRATION which includes domain users, domain admin accounts, service accounts, etc. 
   Typically target OU's that house domain user accounts unless instrcuted otherwise.
   For the password change, you can opt-out of this by commenting out line 21. 
#>

#Log file configuration
$logFile = "C:\temp\reset_pw.txt" # log file

# Set the threshold for the number of days
$thresholdDays = 7

# Make PS digestable. Set password between quotes. Comment out if you dont want to change the account password. NOTE: PS may throw an error if not changing. 
$newPassword = ConvertTo-SecureString "" -AsPlainText -Force 

# Add usernames to exclude here, If targeting a wide range of users and or accounts that should nto be subject to the password change. 
$excludeAccounts = @("user1", "user2", "user3") 

# Set the target OU. Such as "OU=Users,DC=server,DC=local" Place the OU's DN between the quotes. 
$targetOU = "OU=Test,OU=SBSUsers,OU=Users,OU=MyBusiness,DC=clientx,DC=local"

# Get the current date
$currentDate = Get-Date

# Calculate the date threshold
$dateThreshold = $currentDate.AddDays(-$thresholdDays)

# Get users with pwdLastSet more than 7 days ago within the specified OU
$usersToModify = Get-ADUser -Filter * -Properties pwdLastSet, PasswordNeverExpires -SearchBase $targetOU | Where-Object { $excludeAccounts -notcontains $_.SamAccountName -and Enabled -eq $true}

# Set "user must change password at next logon" attribute for each user
foreach ($user in $usersToModify) {
    # Check if PasswordNeverExpires is true, and if so, remove the attribute
    if ($user.PasswordNeverExpires) {
        Set-ADUser -Identity $user.SamAccountName -PasswordNeverExpires $false
        Write-Host "Removed PasswordNeverExpires for user $($user.SamAccountName)"
    }

    # Set "user must change password at next logon" attribute and change accouunt password.
    Set-ADAccountPassword -Identity $user -NewPassword $newPassword -Reset -ErrorAction SilentlyContinue
    Set-ADUser -Identity $user.SamAccountName -ChangePasswordAtLogon $true
    Write-Host "Password reset and changed password policy for user user: $($user.SamAccountName)"
    Add-Content -Path $logFile -Value "[$(Get-Date)] Password reset for user: $($user.SamAccountName)"
    }
