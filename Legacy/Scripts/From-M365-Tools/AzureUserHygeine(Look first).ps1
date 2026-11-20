# User Account Hygiene overview-RR.ps1
<#####################010100101101110110111011010001100101#####################

This script is used to generate the csv file used in the User Account Hygine "UAH" process
  - must be run from Azure AD PS that is connected to MSOnline
  - this script takes considerable time to run. it might feel like it has hung. 
  - It can take more that 5 hours, this is because of the mailbox statistics, we believe.

<#####################010100101101110110111011010001100101#####################>

# a number of company specific strings have been replaced so I can publicky post this here. 
# those fields now say "< redacted value >"
#

# Variables:
  $today = (Get-Date).ToString("yyyy-MM-dd")

# Path to store the csv file   
#
# < redacted value >
# < cut and redacted some local info here sorry > 
# < redacted value >

# Start Log
  Start-Transcript -Path $transcriptlog

  #connect to the MSOL service - it will bomb out if this fails
    Write-host  '  - Connecting to MSOL'
      try {
        Connect-MsolService -Credential $cred -ErrorAction Stop
      }
      catch {
        Write-host  "  -- Failed to connect to MsolService"
        Stop-Transcript
        Return
      }

  # Import PS Session
    Write-host  "  - Importing PS session"
    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell/ -Credential $cred -Authentication Basic -AllowRedirection 
    Import-PSSession $Session

  # Connect to AzureAD
    Write-host  '  - Connecting to AzureAD'
    Connect-AzureAD  -Credential $cred

  # Connect to Exchange Online
    Write-host  '  - Connecting to Exchange Online'
    Connect-ExchangeOnline -Credential $cred -AzureADAuthorizationEndpointUri 'https://login.windows.net/common' -ConnectionUri https://outlook.office365.com/powershell-liveid/ -ExchangeEnvironmentName O365Default -ShowBanner:$False

# Pulling in data
  Write-Output "Pulling info from AD and AAD..."
  # this azure group is the MFA User Group.
    $members = Get-AzureADGroupMember -objectid < redacted value > -all $true
  # this azure group is the Tenant Cloud Backup Users group.
    $bbkmembers = Get-AzureADGroupMember -objectid < redacted value > -all $true
  # this azure group is the Tenant Cloud Backup Shared Mailboxes.
    $bbkSMmembers = Get-AzureADGroupMember -objectid < redacted value > -all $true

  # pull all the data from O365 and store in variables so that the processing goes faster below.
    $users = get-msoluser -All
    $mbxs = Get-Mailbox -ResultSize Unlimited
    $mailusers = Get-MailUser -ResultSize Unlimited

    $LocalSite = (Get-ADDomainController -Discover).Site
    $NewTargetGC = Get-ADDomainController -Discover -Service 6 -SiteName $LocalSite
    IF (!$NewTargetGC)
    { $NewTargetGC = Get-ADDomainController -Discover -Service 6 -NextClosestSite }
    $NewTargetGCHostName = $NewTargetGC.HostName
    $LocalGC = "$NewTargetGCHostName" + ":3268"

Write-Output "Done pulling info from AD and AAD."

# the actual work of pulling out the information and storing it in an array to later export to csv.
$UsersArray = @()
$stopwatch = [system.diagnostics.stopwatch]::startnew()
foreach ($user in $users ){
  if ("None" -ne $user.OverallProvisioningStatus) {
    Write-Host "Working on: " $user.DisplayName
    $missing = $true
    $UserReport = New-Object PSObject
    $strdate = (Get-Date).ToString("dd MMMM yyyy")
    add-member -inputobject $UserReport -membertype noteproperty -name "Date" -value $strdate
    add-member -inputobject $UserReport -membertype noteproperty -name "UPN" -value $user.UserPrincipalName
    add-member -inputobject $UserReport -membertype noteproperty -name "Display Name" -value $user.DisplayName  
    
    # check for mailbox info
    foreach ($mbx in $mbxs) {
      if ($user.UserPrincipalName -eq $mbx.UserPrincipalName) {
        $ou = $mbx.CustomAttribute1
        $role = $mbx.CustomAttribute2
        $mbxtypes = $mbx.RecipientTypeDetails
        $mbxstats = Get-MailboxStatistics -Identity $mbx.UserPrincipalName | Select-Object LastUserActionTime,LastLogonTime,SystemMessageSize
        $LastActionTime = $mbxstats.LastUserActionTime
        $LastLogonTime = $mbxstats.LastLogonTime
        $SystemMessageSize = $mbxstats.SystemMessageSize
        
        #Last Action Time
        If($null -eq $LastActionTime){ 
          add-member -inputobject $UserReport -membertype noteproperty -name "User Action Date" -value "No User Action"
          add-member -inputobject $UserReport -membertype noteproperty -name "User Action Time" -value "00:00"
         }
        Else{ 
          add-member -inputobject $UserReport -membertype noteproperty -name "User Action Date" -value $LastActionTime.ToShortDateString()
          add-member -inputobject $UserReport -membertype noteproperty -name "User Action Time" -value $LastActionTime.ToShortTimeString()
         }
         
        #Last Logon Time
        If($null -eq $LastLogonTime){ 
          add-member -inputobject $UserReport -membertype noteproperty -name "User Logon Date" -value "Never Logged In"
          add-member -inputobject $UserReport -membertype noteproperty -name "Last Logon Time" -value "00:00"
         }
        Else{ 
          add-member -inputobject $UserReport -membertype noteproperty -name "Last Logon Date" -value $LastLogonTime.ToShortDateString()
          add-member -inputobject $UserReport -membertype noteproperty -name "Last Logon Time" -value $LastLogonTime.ToShortTimeString()
         }

        # SystemMessageSize
        If($null -eq $SystemMessageSize){ 
          add-member -inputobject $UserReport -membertype noteproperty -name "Message size" -value "No size"
         }
        Else{ 
          add-member -inputobject $UserReport -membertype noteproperty -name "Message size" -value $SystemMessageSize.Value
         }
        
        # Mailbox Types
        If(!$mbxtypes){
            add-member -inputobject $UserReport -membertype noteproperty -name "Mailbox Type" -value "No Mailbox"
          } 
          Else{
            add-member -inputobject $UserReport -membertype noteproperty -name "Mailbox Type" -value $mbx.RecipientTypeDetails
          } 
        $missing = $false
      }
    }

    # if not a mailbox, it is a < redacted value > mailbox
    if ($missing -eq $true) {
      foreach ($mailuser in $mailusers) {
        if ($user.UserPrincipalName -eq $mailuser.UserPrincipalName) {
          $ou = $mailuser.CustomAttribute1
          $role = $mailuser.CustomAttribute2
          add-member -inputobject $UserReport -membertype noteproperty -name "Last User Action Date" -value "< redacted value > mailbox"
          add-member -inputobject $UserReport -membertype noteproperty -name "Last User Action Time" -value "00:00"
        }
      }
    }
    # < redacted value > have broken this value for certain users. This restores the value.
    if ($ou -eq "A") {
      $ou = "< redacted value >"
    }
    
    # check for blank OU's. If so then either cloud-only or we need to pull the OU from local AD
    if ($null -eq $ou -or $ou -eq "") {
      if ($null -eq $user.LastDirSyncTime) {
        $ou = "cloud-only account"
      }
      elseif (Get-ADObject -Server $LocalGC -Filter 'UserPrincipalName -eq $user.UserPrincipalName') {
        $dn = Get-ADObject -Server $LocalGC -Filter 'UserPrincipalName -eq $user.UserPrincipalName' -Properties CanonicalName
        $ou = $dn.CanonicalName.Substring(0, $dn.CanonicalName.lastIndexOf('/'))
      }
      else {
        $ou = "unknown"
      }
    }
        
    add-member -inputobject $UserReport -membertype noteproperty -name "Fields per OU" -value $ou
    add-member -inputobject $UserReport -membertype noteproperty -name "MFA_Activated" -value $false
    # check if user is member of MFA group
    foreach ($member in $members) { 
      if ($user.UserPrincipalName -eq $member.UserPrincipalName) {
        $UserReport.MFA_Activated = $true
      }
    }
    # check if MFA is configured
    if ( -not ([string]::IsNullOrEmpty($user.StrongAuthenticationMethods))) {
      add-member -inputobject $UserReport -membertype noteproperty -name "MFA configured" -value $true
    } else {
      add-member -inputobject $UserReport -membertype noteproperty -name "MFA configured" -value $false
    }
    # export the OM ROLE status
    if ($role -eq "OM ROLE" -or $role -eq "SERVICE") {
      $role = $true
    } else {
      $role = $false
    }
    add-member -inputobject $UserReport -membertype noteproperty -name "OM Role account" -value $role
    
    If ($User.BlockCredential -eq $true) {
      add-member -inputobject $UserReport -membertype noteproperty -name "Disabled" -value $true
    } else {
      add-member -inputobject $UserReport -membertype noteproperty -name "Disabled" -value $false
    }
    
    If ($User.licenses.accountskuid -contains "emailnet:EMS") {
      add-member -inputobject $UserReport -membertype noteproperty -name "MFA License" -value "True"
    } else {
      add-member -inputobject $UserReport -membertype noteproperty -name "MFA License" -value "False"
    }

    If ($User.licenses.accountskuid -contains "emailnet:OFFICESUBSCRIPTION") {
      add-member -inputobject $UserReport -membertype noteproperty -name "ProPlus License" -value "True"
    } else {
      add-member -inputobject $UserReport -membertype noteproperty -name "ProPlus License" -value "False"
    }
 
    #add default MFA type setup
    $DefaultMFAMethod=($User.StrongAuthenticationMethods | Where-Object{$_.IsDefault -eq "True"}).MethodType
    If ($null -eq $DefaultMFAMethod) {
      add-member -inputobject $UserReport -membertype noteproperty -name "Default MFA Type" -value "False"
    } else {
      add-member -inputobject $UserReport -membertype noteproperty -name "Default MFA Type" -value "$DefaultMFAMethod"
    }
    
    #Last Password Change Timestamp
    $lpct = $user.LastPasswordChangeTimestamp
    If($null -eq $lpct){ 
      add-member -inputobject $UserReport -membertype noteproperty -name "Last Password Change Date" -value "Never"
      add-member -inputobject $UserReport -membertype noteproperty -name "Last Password Change Time" -value "00:00"
     }
    Else{ 
      add-member -inputobject $UserReport -membertype noteproperty -name "Last Password Change Date" -value $lpct.ToShortDateString()
      add-member -inputobject $UserReport -membertype noteproperty -name "Last Password Change Time" -value $lpct.ToShortTimeString()
     }
    
    # Users in the Group < redacted value > Users or Group < redacted value > Shared Mailboxes.
      add-member -inputobject $UserReport -membertype noteproperty -name "< redacted value >" -value $false
      # check if user is member of Tenant < redacted value > Users.
        foreach ($member in $bbkmembers){ 
          if ($user.UserPrincipalName -eq $member.UserPrincipalName) {
            $UserReport.< redacted value > = $true
          }
        } 
      # check if user is member of Tenant < redacted value > Shared Mailboxes.
        foreach ($member in $bbkSMmembers){ 
          if ($user.UserPrincipalName -eq $member.UserPrincipalName) {
            $UserReport.< redacted value > = $true
          }
        } 
    
    $UsersArray += $UserReport
    $UserReport = $null
    $ou = $null
    $role = $null
  }
}

$stopwatch.stop()
$time = $stopwatch.elapsed.totalminutes
Write-Output "This script took $time minutes to complete."
$UsersArray.count
$UsersArray |Export-Csv -NoTypeInformation $csvfile
# import into Excel as seperated by commas. Use a new tab otherwise data imports badly. (deleting the cells does not fix it)
# sort with headers by Disabled,OU,O365_MFA_Users,MFAConfigured,UPN in that order
# subtotal by OU count
# then subtotal by O365_MFA_Users count

#End Log
Write-Output "`nCompleted batch job."
Write-Output " "
Stop-Transcript
