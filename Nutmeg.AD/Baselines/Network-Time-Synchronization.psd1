# Baseline: Network - Time Synchronization (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'network-time-synchronization'
    Name        = 'Network - Time Synchronization'
    Version     = '0.7.1'
    Description = 'Windows NTP client: domain hierarchy (NT5DS), poll every 1024 seconds; location provider on and automatic time zone updates set to manual start.'
    Source      = 'Legacy/GPO-Reports/Network - Time Synchronization.html'
    Requires    = @()
    Notes       = @('Linked at Devices only, never the domain root or Domain Controllers: NT5DS on the PDC would leave the domain without a time source.',
                    'With NT5DS the server name is ignored; it is kept so the GPO matches the report.')
    Parameters  = @(
        @{ Name = 'NtpServer'; Prompt = 'NTP server (ignored with NT5DS)'; Type = 'String'; Default = '{Session:Pdc},0x1' }
    )
    Settings    = @(
        @{ Id = 'ntp-client'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Windows Time Service/Time Providers: Configure Windows NTP Client = Enabled ({NtpServer}, NT5DS, poll 1024)'
           Values = @(
               @{ Key = 'HKLM\Software\Policies\Microsoft\W32Time\Parameters'; ValueName = 'NtpServer'; Type = 'String'; Value = '{NtpServer}' }
               @{ Key = 'HKLM\Software\Policies\Microsoft\W32Time\Parameters'; ValueName = 'Type'; Type = 'String'; Value = 'NT5DS' }
               @{ Key = 'HKLM\Software\Policies\Microsoft\W32Time\TimeProviders\NtpClient'; ValueName = 'CrossSiteSyncFlags'; Type = 'DWord'; Value = 2 }
               @{ Key = 'HKLM\Software\Policies\Microsoft\W32Time\TimeProviders\NtpClient'; ValueName = 'ResolvePeerBackoffMinutes'; Type = 'DWord'; Value = 15 }
               @{ Key = 'HKLM\Software\Policies\Microsoft\W32Time\TimeProviders\NtpClient'; ValueName = 'ResolvePeerBackoffMaxTimes'; Type = 'DWord'; Value = 7 }
               @{ Key = 'HKLM\Software\Policies\Microsoft\W32Time\TimeProviders\NtpClient'; ValueName = 'SpecialPollInterval'; Type = 'DWord'; Value = 1024 }
               @{ Key = 'HKLM\Software\Policies\Microsoft\W32Time\TimeProviders\NtpClient'; ValueName = 'EventLogFlags'; Type = 'DWord'; Value = 0 }
           ) }
        @{ Id = 'location-provider'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'Windows Components/Location and Sensors/Windows Location Provider: Turn off Windows Location Provider = Disabled'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\LocationAndSensors'; ValueName = 'DisableWindowsLocationProvider'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'tzautoupdate'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: tzautoupdate Start = 3 (manual)'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Services\tzautoupdate'; ValueName = 'Start'; Type = 'DWord'; Value = 3; Action = 'Update' }
    )
}
