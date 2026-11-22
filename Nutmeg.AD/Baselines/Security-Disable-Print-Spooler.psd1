# Baseline: Security - Disable Print Spooler (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'security-disable-print-spooler'
    Name        = 'Security - Disable Print Spooler'
    Version     = '0.7.1'
    Description = 'The Print Spooler service is disabled.'
    Source      = 'Legacy/GPO-Reports/Security - Disable Print Spooler.html'
    Requires    = @()
    Notes       = @('For DCs and servers that do not print (Domain Controllers, Devices/Member Servers).',
                    'The report gave the client''s Domain Admins full control of the service; the baseline uses the built-in Administrators and SYSTEM, as GPMC does by default.')
    Parameters  = @()
    Settings    = @(
        @{ Id = 'spooler-disabled'; Kind = 'Service'; Side = 'Computer'; Tags = @()
           Title = 'System Services: Print Spooler = Disabled'
           Service = 'Spooler'; StartMode = 'Disabled' }
    )
}
