# Baseline: Security - LDAPS Hardening (DC's) (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'security-ldaps-hardening-dcs'
    Name        = 'Security - LDAPS Hardening (DC''s)'
    Version     = '0.7.1'
    Description = 'Domain controllers require LDAP signing and always require channel binding.'
    Source      = 'Legacy/GPO-Reports/Security - LDAPS Hardening (DC''s).html'
    Requires    = @()
    Notes       = @('Linked at Domain Controllers. Run ready first: unsigned and non-channel-bound binds (events 2889, 3039) stop working.')
    Parameters  = @()
    Settings    = @(
        @{ Id = 'server-signing'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'Domain controller: LDAP server signing requirements = Require signing'
           Key = 'MACHINE\System\CurrentControlSet\Services\NTDS\Parameters\LDAPServerIntegrity'; Type = 'DWord'; Value = 2 }
        @{ Id = 'channel-binding'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'Domain controller: LDAP server channel binding token requirements = Always'
           Key = 'MACHINE\System\CurrentControlSet\Services\NTDS\Parameters\LdapEnforceChannelBinding'; Type = 'DWord'; Value = 2 }
    )
}
