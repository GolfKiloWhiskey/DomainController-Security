# Baseline: Security - Domain Auditing (DC's) (Huntress minimum + DC report extras). Format: Core\Baseline.ps1.
@{
    Id          = 'security-domain-auditing-dcs'
    Name        = 'Security - Domain Auditing (DC''s)'
    Version     = '0.7.2'
    Description = 'Advanced audit policy for domain controllers: Huntress minimum, DC report extras (account logon/management, DS access/replication, logon/logoff, policy change), Process Creation for PowerShell logging, and forced audit subcategories.'
    Source      = 'Legacy/GPO-Reports/Security - Domain Auditing (DC''s).html'
    Requires    = @()
    Notes       = @('Linked at Domain Controllers (Data\GpoDefaultLinks.csv).',
                    'Starts from the Huntress minimum (Update-AuditPol-HuntressDefaults), adds the DC report extras and Process Creation, and forces audit policy subcategories.')
    Parameters  = @()
    Settings    = @(
        # Force subcategory settings
        @{ Id = 'force-audit-subcategory'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'Audit: Force audit policy subcategory settings (Windows Vista or later) to override audit policy category settings = Enabled'
           Key = 'MACHINE\System\CurrentControlSet\Control\Lsa\SCENoApplyLegacyAuditPolicy'; Type = 'DWord'; Value = 1 }
        # Account Logon
        @{ Id = 'credential-validation'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Account Logon: Audit Credential Validation = Success, Failure'; Subcategory = 'Credential Validation'; Setting = 'SuccessAndFailure' }
        @{ Id = 'kerberos-authentication-service'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Account Logon: Audit Kerberos Authentication Service = Success, Failure'; Subcategory = 'Kerberos Authentication Service'; Setting = 'SuccessAndFailure' }
        @{ Id = 'kerberos-service-ticket-operations'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Account Logon: Audit Kerberos Service Ticket Operations = Success, Failure'; Subcategory = 'Kerberos Service Ticket Operations'; Setting = 'SuccessAndFailure' }
        @{ Id = 'other-account-logon-events'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Account Logon: Audit Other Account Logon Events = Success, Failure'; Subcategory = 'Other Account Logon Events'; Setting = 'SuccessAndFailure' }
        # Account Management
        @{ Id = 'application-group-management'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Account Management: Audit Application Group Management = Success, Failure'; Subcategory = 'Application Group Management'; Setting = 'SuccessAndFailure' }
        @{ Id = 'computer-account-management'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Account Management: Audit Computer Account Management = Success, Failure'; Subcategory = 'Computer Account Management'; Setting = 'SuccessAndFailure' }
        @{ Id = 'distribution-group-management'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Account Management: Audit Distribution Group Management = Success, Failure'; Subcategory = 'Distribution Group Management'; Setting = 'SuccessAndFailure' }
        @{ Id = 'other-account-management-events'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Account Management: Audit Other Account Management Events = Success, Failure'; Subcategory = 'Other Account Management Events'; Setting = 'SuccessAndFailure' }
        @{ Id = 'security-group-management'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Account Management: Audit Security Group Management = Success, Failure'; Subcategory = 'Security Group Management'; Setting = 'SuccessAndFailure' }
        @{ Id = 'user-account-management'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Account Management: Audit User Account Management = Success, Failure'; Subcategory = 'User Account Management'; Setting = 'SuccessAndFailure' }
        # Detailed Tracking
        @{ Id = 'plug-and-play-events'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Detailed Tracking: Audit Plug and Play Events = Success'; Subcategory = 'Plug and Play Events'; Setting = 'Success' }
        @{ Id = 'process-creation'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Detailed Tracking: Audit Process Creation = Success'; Subcategory = 'Process Creation'; Setting = 'Success' }
        # DS Access
        @{ Id = 'detailed-directory-service-replication'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'DS Access: Audit Detailed Directory Service Replication = Failure'; Subcategory = 'Detailed Directory Service Replication'; Setting = 'Failure' }
        @{ Id = 'directory-service-access'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'DS Access: Audit Directory Service Access = Success, Failure'; Subcategory = 'Directory Service Access'; Setting = 'SuccessAndFailure' }
        @{ Id = 'directory-service-changes'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'DS Access: Audit Directory Service Changes = Success, Failure'; Subcategory = 'Directory Service Changes'; Setting = 'SuccessAndFailure' }
        @{ Id = 'directory-service-replication'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'DS Access: Audit Directory Service Replication = Failure'; Subcategory = 'Directory Service Replication'; Setting = 'Failure' }
        # Logon/Logoff
        @{ Id = 'account-lockout'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Logon/Logoff: Audit Account Lockout = Success, Failure'; Subcategory = 'Account Lockout'; Setting = 'SuccessAndFailure' }
        @{ Id = 'group-membership'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Logon/Logoff: Audit Group Membership = Success, Failure'; Subcategory = 'Group Membership'; Setting = 'SuccessAndFailure' }
        @{ Id = 'logoff'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Logon/Logoff: Audit Logoff = Success, Failure'; Subcategory = 'Logoff'; Setting = 'SuccessAndFailure' }
        @{ Id = 'logon'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Logon/Logoff: Audit Logon = Success, Failure'; Subcategory = 'Logon'; Setting = 'SuccessAndFailure' }
        @{ Id = 'network-policy-server'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Logon/Logoff: Audit Network Policy Server = Success, Failure'; Subcategory = 'Network Policy Server'; Setting = 'SuccessAndFailure' }
        @{ Id = 'other-logon-logoff-events'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Logon/Logoff: Audit Other Logon/Logoff Events = Success, Failure'; Subcategory = 'Other Logon/Logoff Events'; Setting = 'SuccessAndFailure' }
        @{ Id = 'special-logon'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Logon/Logoff: Audit Special Logon = Success, Failure'; Subcategory = 'Special Logon'; Setting = 'SuccessAndFailure' }
        # Object Access
        @{ Id = 'detailed-file-share'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Object Access: Audit Detailed File Share = Success, Failure'; Subcategory = 'Detailed File Share'; Setting = 'SuccessAndFailure' }
        @{ Id = 'file-share'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Object Access: Audit File Share = Success, Failure'; Subcategory = 'File Share'; Setting = 'SuccessAndFailure' }
        @{ Id = 'filtering-platform-connection'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Object Access: Audit Filtering Platform Connection = Failure'; Subcategory = 'Filtering Platform Connection'; Setting = 'Failure' }
        @{ Id = 'kernel-object'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Object Access: Audit Kernel Object = Success, Failure'; Subcategory = 'Kernel Object'; Setting = 'SuccessAndFailure' }
        @{ Id = 'other-object-access-events'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Object Access: Audit Other Object Access Events = Success, Failure'; Subcategory = 'Other Object Access Events'; Setting = 'SuccessAndFailure' }
        @{ Id = 'removable-storage'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Object Access: Audit Removable Storage = Success, Failure'; Subcategory = 'Removable Storage'; Setting = 'SuccessAndFailure' }
        # Policy Change
        @{ Id = 'audit-policy-change'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Policy Change: Audit Audit Policy Change = Success, Failure'; Subcategory = 'Audit Policy Change'; Setting = 'SuccessAndFailure' }
        @{ Id = 'authentication-policy-change'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Policy Change: Audit Authentication Policy Change = Success, Failure'; Subcategory = 'Authentication Policy Change'; Setting = 'SuccessAndFailure' }
        @{ Id = 'authorization-policy-change'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Policy Change: Audit Authorization Policy Change = Success, Failure'; Subcategory = 'Authorization Policy Change'; Setting = 'SuccessAndFailure' }
        @{ Id = 'filtering-platform-policy-change'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Policy Change: Audit Filtering Platform Policy Change = Success'; Subcategory = 'Filtering Platform Policy Change'; Setting = 'Success' }
        @{ Id = 'mpssvc-rule-level-policy-change'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Policy Change: Audit MPSSVC Rule-Level Policy Change = Success, Failure'; Subcategory = 'MPSSVC Rule-Level Policy Change'; Setting = 'SuccessAndFailure' }
        @{ Id = 'other-policy-change-events'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Policy Change: Audit Other Policy Change Events = Success, Failure'; Subcategory = 'Other Policy Change Events'; Setting = 'SuccessAndFailure' }
        # Privilege Use
        @{ Id = 'sensitive-privilege-use'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Privilege Use: Audit Sensitive Privilege Use = Success, Failure'; Subcategory = 'Sensitive Privilege Use'; Setting = 'SuccessAndFailure' }
        # System
        @{ Id = 'other-system-events'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'System: Audit Other System Events = Success, Failure'; Subcategory = 'Other System Events'; Setting = 'SuccessAndFailure' }
        @{ Id = 'security-state-change'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'System: Audit Security State Change = Success'; Subcategory = 'Security State Change'; Setting = 'Success' }
        @{ Id = 'security-system-extension'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'System: Audit Security System Extension = Success'; Subcategory = 'Security System Extension'; Setting = 'Success' }
        @{ Id = 'system-integrity'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'System: Audit System Integrity = Success, Failure'; Subcategory = 'System Integrity'; Setting = 'SuccessAndFailure' }
    )
}
