# Baseline: Devices - Power Profile (Workstations) (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'devices-power-profile-workstations'
    Name        = 'Devices - Power Profile (Workstations)'
    Version     = '0.7.1'
    Description = 'Desktop workstation power profile: High Performance plan, sleep/standby/hibernate/hybrid sleep off on AC and battery, and Sleep and Hibernate hidden from the power menu.'
    Source      = 'Legacy/GPO-Reports/Devices - Power Profile (Workstations).html'
    Requires    = @()
    Notes       = @('Linked at Devices/Workstations/Desktops (Data\GpoDefaultLinks.csv). Meant for desktops, not laptops.')
    Parameters  = @()
    Settings    = @(
        @{ Id = 'active-power-plan'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management: Select an active power plan = Enabled (High Performance)'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings'; ValueName = 'ActivePowerScheme'; Type = 'String'; Value = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' } ) }
        @{ Id = 'standby-states-dc'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management/Sleep Settings: Allow standby states (S1-S3) when sleeping (on battery) = Disabled'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings\abfc2519-3608-4c2a-94ea-171b0ed546ab'; ValueName = 'DCSettingIndex'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'standby-states-ac'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management/Sleep Settings: Allow standby states (S1-S3) when sleeping (plugged in) = Disabled'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings\abfc2519-3608-4c2a-94ea-171b0ed546ab'; ValueName = 'ACSettingIndex'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'hibernate-timeout-dc'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management/Sleep Settings: Specify the system hibernate timeout (on battery) = Enabled (0 s)'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings\9d7815a6-7ee4-497e-8888-515a05f02364'; ValueName = 'DCSettingIndex'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'hibernate-timeout-ac'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management/Sleep Settings: Specify the system hibernate timeout (plugged in) = Enabled (0 s)'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings\9d7815a6-7ee4-497e-8888-515a05f02364'; ValueName = 'ACSettingIndex'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'sleep-timeout-dc'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management/Sleep Settings: Specify the system sleep timeout (on battery) = Enabled (0 s)'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings\29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ValueName = 'DCSettingIndex'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'sleep-timeout-ac'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management/Sleep Settings: Specify the system sleep timeout (plugged in) = Enabled (0 s)'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings\29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ValueName = 'ACSettingIndex'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'unattended-sleep-dc'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management/Sleep Settings: Specify the unattended sleep timeout (on battery) = Enabled (0 s)'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings\7bc4a2f9-d8fc-4469-b07b-33eb785aaca0'; ValueName = 'DCSettingIndex'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'unattended-sleep-ac'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management/Sleep Settings: Specify the unattended sleep timeout (plugged in) = Enabled (0 s)'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings\7bc4a2f9-d8fc-4469-b07b-33eb785aaca0'; ValueName = 'ACSettingIndex'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'hybrid-sleep-off-dc'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management/Sleep Settings: Turn off hybrid sleep (on battery) = Enabled'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings\94ac6d29-73ce-41a6-809f-6363ba21b47e'; ValueName = 'DCSettingIndex'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'hybrid-sleep-off-ac'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'System/Power Management/Sleep Settings: Turn off hybrid sleep (plugged in) = Enabled'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Power\PowerSettings\94ac6d29-73ce-41a6-809f-6363ba21b47e'; ValueName = 'ACSettingIndex'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'hide-hibernate-menu'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'Windows Components/File Explorer: Show hibernate in the power options menu = Disabled'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\Explorer'; ValueName = 'ShowHibernateOption'; Type = 'DWord'; Value = 0 } ) }
        @{ Id = 'hide-sleep-menu'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'Windows Components/File Explorer: Show sleep in the power options menu = Disabled'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\Explorer'; ValueName = 'ShowSleepOption'; Type = 'DWord'; Value = 0 } ) }
    )
}
