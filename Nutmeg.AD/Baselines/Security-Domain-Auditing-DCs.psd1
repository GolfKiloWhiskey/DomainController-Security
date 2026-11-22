# Baseline: Security - Domain Auditing (DC's) (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'security-domain-auditing-dcs'
    Name        = 'Security - Domain Auditing (DC''s)'
    Version     = '0.7.1'
    Description = 'Advanced audit policy for domain controllers: account logon, account management, DS access, logon/logoff and policy change.'
    Source      = 'Legacy/GPO-Reports/Security - Domain Auditing (DC''s).html'
    Requires    = @()
    Notes       = @('Linked at Domain Controllers.', 'As in the report. The Huntress minimum (TOOL-LIST, audit policy per role) is added later as a new version of this baseline.')
    Parameters  = @()
    Settings    = @(
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
        @{ Id = 'other-logon-logoff-events'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Logon/Logoff: Audit Other Logon/Logoff Events = Success, Failure'; Subcategory = 'Other Logon/Logoff Events'; Setting = 'SuccessAndFailure' }
        @{ Id = 'special-logon'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Logon/Logoff: Audit Special Logon = Success, Failure'; Subcategory = 'Special Logon'; Setting = 'SuccessAndFailure' }
        # Policy Change
        @{ Id = 'audit-policy-change'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Policy Change: Audit Audit Policy Change = Success, Failure'; Subcategory = 'Audit Policy Change'; Setting = 'SuccessAndFailure' }
        @{ Id = 'authentication-policy-change'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Policy Change: Audit Authentication Policy Change = Success, Failure'; Subcategory = 'Authentication Policy Change'; Setting = 'SuccessAndFailure' }
        @{ Id = 'authorization-policy-change'; Kind = 'Audit'; Side = 'Computer'; Tags = @(); Title = 'Policy Change: Audit Authorization Policy Change = Success, Failure'; Subcategory = 'Authorization Policy Change'; Setting = 'SuccessAndFailure' }
    )
}
