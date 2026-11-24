# Baseline: Group Policy Processing (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'group-policy-processing'
    Name        = 'Group Policy Processing'
    Version     = '0.7.1'
    Description = 'Reapply registry and security policies even when unchanged, refresh every 15 minutes (+ 30 random) on computers and DCs, wait up to 60 seconds for startup policy processing, and wait for the network at startup and logon.'
    Source      = 'Legacy/GPO-Reports/Group Policy Processing.html'
    Requires    = @()
    Notes       = @('Linked at the domain root (Data\GpoDefaultLinks.csv).')
    Parameters  = @(
        @{ Name = 'RefreshMinutes'; Prompt = 'Refresh interval for computers (minutes)'; Type = 'Int'; Default = 15; Min = 0; Max = 44640 }
        @{ Name = 'RefreshOffsetMinutes'; Prompt = 'Random offset added to computer refresh (minutes)'; Type = 'Int'; Default = 30; Min = 0; Max = 1440 }
        @{ Name = 'DcRefreshMinutes'; Prompt = 'Refresh interval for domain controllers (minutes)'; Type = 'Int'; Default = 15; Min = 0; Max = 44640 }
        @{ Name = 'DcRefreshOffsetMinutes'; Prompt = 'Random offset added to DC refresh (minutes)'; Type = 'Int'; Default = 30; Min = 0; Max = 1440 }
        @{ Name = 'StartupWaitSeconds'; Prompt = 'Startup policy processing wait time (seconds)'; Type = 'Int'; Default = 60; Min = 0; Max = 600 }
    )
    Settings    = @(
        @{ Id = 'registry-policy-processing'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Group Policy: Configure registry policy processing = Enabled (process even if unchanged, background on)'
           Values = @(
               @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\Group Policy\{35378EAC-683F-11D2-A89A-00C04FBBCFA2}'; ValueName = 'NoBackgroundPolicy'; Type = 'DWord'; Value = 0 }
               @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\Group Policy\{35378EAC-683F-11D2-A89A-00C04FBBCFA2}'; ValueName = 'NoGPOListChanges'; Type = 'DWord'; Value = 0 }
           ) }
        @{ Id = 'security-policy-processing'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Group Policy: Configure security policy processing = Enabled (process even if unchanged, background on)'
           Values = @(
               @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\Group Policy\{827D319E-6EAC-11D2-A4EA-00C04F79F83A}'; ValueName = 'NoBackgroundPolicy'; Type = 'DWord'; Value = 0 }
               @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\Group Policy\{827D319E-6EAC-11D2-A4EA-00C04F79F83A}'; ValueName = 'NoGPOListChanges'; Type = 'DWord'; Value = 0 }
           ) }
        @{ Id = 'refresh-computers'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Group Policy: Set Group Policy refresh interval for computers = Enabled ({RefreshMinutes} min, +{RefreshOffsetMinutes} random)'
           Values = @(
               @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\System'; ValueName = 'GroupPolicyRefreshTime'; Type = 'DWord'; Value = '{RefreshMinutes}' }
               @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\System'; ValueName = 'GroupPolicyRefreshTimeOffset'; Type = 'DWord'; Value = '{RefreshOffsetMinutes}' }
           ) }
        @{ Id = 'refresh-dcs'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Group Policy: Set Group Policy refresh interval for domain controllers = Enabled ({DcRefreshMinutes} min, +{DcRefreshOffsetMinutes} random)'
           Values = @(
               @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\System'; ValueName = 'GroupPolicyRefreshTimeDC'; Type = 'DWord'; Value = '{DcRefreshMinutes}' }
               @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\System'; ValueName = 'GroupPolicyRefreshTimeOffsetDC'; Type = 'DWord'; Value = '{DcRefreshOffsetMinutes}' }
           ) }
        @{ Id = 'startup-wait'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Group Policy: Specify startup policy processing wait time = Enabled ({StartupWaitSeconds} s)'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\System'; ValueName = 'GpNetworkStartTimeoutPolicyValue'; Type = 'DWord'; Value = '{StartupWaitSeconds}' } ) }
        @{ Id = 'wait-for-network'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Logon: Always wait for the network at computer startup and logon = Enabled'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon'; ValueName = 'SyncForegroundPolicy'; Type = 'DWord'; Value = 1 } ) }
    )
}
