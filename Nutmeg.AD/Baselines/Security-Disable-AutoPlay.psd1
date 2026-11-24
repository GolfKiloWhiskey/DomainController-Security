# Baseline: Security - Disable AutoPlay (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'security-disable-autoplay'
    Name        = 'Security - Disable AutoPlay'
    Version     = '0.7.1'
    Description = 'Prevent AutoRun commands from executing and disable AutoPlay on all drives.'
    Source      = 'Legacy/GPO-Reports/Security - Disable AutoPlay.html'
    Requires    = @()
    Notes       = @('Linked at Devices/Workstations and Devices/Member Servers (Data\GpoDefaultLinks.csv).')
    Parameters  = @()
    Settings    = @(
        @{ Id = 'autorun-behavior'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'Windows Components/AutoPlay Policies: Set the default behavior for AutoRun = Enabled (Do not execute any autorun commands)'
           Values = @( @{ Key = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; ValueName = 'NoAutorun'; Type = 'DWord'; Value = 1 } ) }
        @{ Id = 'autoplay-off'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'Windows Components/AutoPlay Policies: Turn off Autoplay = Enabled (All drives)'
           Values = @( @{ Key = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; ValueName = 'NoDriveTypeAutoRun'; Type = 'DWord'; Value = 255 } ) }   # 0xFF
    )
}
