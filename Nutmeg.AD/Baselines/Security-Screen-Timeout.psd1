# Baseline: Security - Screen Timeout (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'security-screen-timeout'
    Name        = 'Security - Screen Timeout'
    Version     = '0.7.1'
    Description = 'A password-protected screen saver (scrnsave.scr) after a set time, 900 seconds by default.'
    Source      = 'Legacy/GPO-Reports/Security - Screen Timeout.html'
    Requires    = @()
    Notes       = @('A user setting: linked at Users.')
    Parameters  = @(
        @{ Name = 'TimeoutSeconds'; Prompt = 'Seconds before the screen locks'; Type = 'Int'; Default = 900; Min = 60; Max = 7200 }
    )
    Settings    = @(
        @{ Id = 'screensaver-on'; Kind = 'Policy'; Side = 'User'; Tags = @()
           Title = 'Control Panel/Personalization: Enable screen saver = Enabled'
           Values = @( @{ Key = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'; ValueName = 'ScreenSaveActive'; Type = 'String'; Value = '1' } ) }
        @{ Id = 'screensaver-file'; Kind = 'Policy'; Side = 'User'; Tags = @()
           Title = 'Control Panel/Personalization: Force specific screen saver = Enabled, scrnsave.scr'
           Values = @( @{ Key = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'; ValueName = 'SCRNSAVE.EXE'; Type = 'String'; Value = 'scrnsave.scr' } ) }
        @{ Id = 'screensaver-password'; Kind = 'Policy'; Side = 'User'; Tags = @()
           Title = 'Control Panel/Personalization: Password protect the screen saver = Enabled'
           Values = @( @{ Key = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'; ValueName = 'ScreenSaverIsSecure'; Type = 'String'; Value = '1' } ) }
        @{ Id = 'screensaver-timeout'; Kind = 'Policy'; Side = 'User'
           Title = 'Control Panel/Personalization: Screen saver timeout = Enabled, {TimeoutSeconds} seconds'
           Values = @( @{ Key = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'; ValueName = 'ScreenSaveTimeOut'; Type = 'String'; Value = '{TimeoutSeconds}' } )
           Tags = @('NIST800-53:AC-11', 'NIST800-171:3.1.10', 'HIPAA:164.312(a)(2)(iii)') }
    )
}
