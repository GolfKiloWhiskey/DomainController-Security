# Baseline: Security - LDAPS Hardening (Devices) (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'security-ldaps-hardening-devices'
    Name        = 'Security - LDAPS Hardening (Devices)'
    Version     = '0.7.1'
    Description = 'Workstations and member servers require LDAP client signing.'
    Source      = 'Legacy/GPO-Reports/Security - LDAPS Hardening (Devices).html'
    Requires    = @()
    Notes       = @('Linked at Devices/Workstations and Devices/Member Servers.')
    Parameters  = @()
    Settings    = @(
        @{ Id = 'client-signing'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'Network security: LDAP client signing requirements = Require signing'
           Key = 'MACHINE\System\CurrentControlSet\Services\LDAP\LDAPClientIntegrity'; Type = 'DWord'; Value = 2 }
    )
}
