# Legacy intake index

Every script, screenshot and GPO report sent for the toolkit, and where it goes. Nothing in `Legacy/` is
loaded by `Nutmeg.AD`. Once an item is ported or its deletion is confirmed it is removed from this
folder (git history keeps it) and its row stays here.

Statuses: **Ported** (tool id), **To do**, **Reference** (kept to read, not run), **Deleted**, **Retire**, **Keep outside**.

## From M365-Tools

Of the scripts M365-Tools set aside as "keep outside", only this one is useful for DC build and
reporting. The rest were reviewed with Cliff and dropped (Entra Connect health and migration, MDM join
and remediation, the Office Bing policy, the AD/MSOnline hygiene export).

| Script | Status | What it does | Notes |
| --- | --- | --- | --- |
| [Get-EventIDHashTables.ps1](Scripts/Get-EventIDHashTables.ps1) | To do | Reads a Security event (4625) into its named fields | Seed for an event lookup helper in the core (health checks, DC security event reports) |

## Your scripts

### AD report

| Script | Status | What it does | Notes |
| --- | --- | --- | --- |
| [AD-Advanced-Report.ps1](Scripts/AD-Report/AD-Advanced-Report.ps1) | To do (`ad-report`) | v4.5. One self-contained HTML AD health and inventory report with executive summary, findings (and JSON), DC health, replication, sites and DNS, users, groups, privileged access, security, computers and LAPS, OUs and GPOs | Kept whole, like the IT Glue engine in M365-Tools: the tool asks its questions through the core and runs it in its own process with `-NoPrompt`. Read only. No client data in it |

### Personal repository

Scrubbed before commit: a client domain and OU, a hard-coded password, example rows from a real
environment, and a personal email address in the headers (now the work address). Nothing else changed.
**Ask** means Cliff decides whether general AD admin is in scope.

| Script | Status | What it does | Notes |
| --- | --- | --- | --- |
| [Update-AuditPol-HuntressDefaults.ps1](Scripts/Personal-Repo/Update-AuditPol-HuntressDefaults.ps1) | To do (baseline) | Checks and applies 59 advanced audit subcategories with auditpol, to Huntress recommendations | Becomes an audit baseline, not auditpol on the machine (hardening is GPO). Overlaps the three Domain Auditing GPOs; it turns Process Creation off, but the PowerShell logging GPO turns on command lines in process creation events, which need it. Merge decided with Cliff |
| [CreateGPO-SSL_TLS-Disable.ps1](Scripts/Personal-Repo/CreateGPO-SSL_TLS-Disable.ps1) | To do (baseline) | Adds registry preferences to a GPO (Registry.xml) that turn off SSL 2.0/3.0 and TLS 1.0/1.1 | New baseline "Security - SCHANNEL Hardening". Its Registry.xml writer is a reference for `gpo-build` |
| [Audit-SslTlsCiphersAndProtocols.ps1](Scripts/Personal-Repo/Audit-SslTlsCiphersAndProtocols.ps1) | To do | Audits SSL/TLS on one machine: SCHANNEL protocols with OS defaults, .NET strong crypto, FIPS, cipher suites, curves, HTTPS bindings, RDP and WinRM security, certificate health | Goes into `ready` (check DCs before the SCHANNEL baseline), run on each DC |
| [Enable-UserKerberosEncryption.ps1](Scripts/Personal-Repo/Enable-UserKerberosEncryption.ps1) | To do | Sets AES encryption types on the users in an OU | Fix step for `ready`: accounts without AES before the Kerberos Encryption baseline |
| [Get-ADGroupMembers-PartialGroupNaming-MENU.ps1](Scripts/Personal-Repo/Get-ADGroupMembers-PartialGroupNaming-MENU.ps1) | To do | Finds groups by part of a name; exports members of one or all | `ad-groups` |
| [Get-ADGroupMemberAudit.ps1](Scripts/Personal-Repo/Get-ADGroupMemberAudit.ps1) | To do | Group member export with a menu | `ad-groups`; older version of the one above |
| [Get-DomainAdminsUsers_ThenTheirGroups.ps1](Scripts/Personal-Repo/Get-DomainAdminsUsers_ThenTheirGroups.ps1) | To do | Domain Admins members and each one's groups | `ad-groups` (privileged view) |
| [GetDomainAdmins.ps1](Scripts/Personal-Repo/GetDomainAdmins.ps1) | Delete | Lists Domain Admins | One-liner; covered by the AD report and `ad-groups` |
| [MigrateFSMOtoNewServer.ps1](Scripts/Personal-Repo/MigrateFSMOtoNewServer.ps1) | Ask | Moves all five FSMO roles to a named DC | Possible `dc-fsmo` (when a new DC replaces an old one). Post-build, but close to DC build work |
| [Get-Schema_Forest-ThenUpgradeBothToNewestLevel.ps1](Scripts/Personal-Repo/Get-Schema_Forest-ThenUpgradeBothToNewestLevel.ps1) | Ask | Shows schema and forest level; upgrades schema and raises the forest level | Raising domain and forest levels could be a tool; the schema upgrade (adprep) is DC build work and stays manual |
| [Get-ADSchemaVersion.ps1](Scripts/Personal-Repo/Get-ADSchemaVersion.ps1) | Delete | Schema version mapped to a Windows Server version | Covered by the AD report |
| [GetSchemaVersion.ps1](Scripts/Personal-Repo/GetSchemaVersion.ps1) | Delete | Schema version | Covered by the AD report |
| [GetForestFunctionalLevel.ps1](Scripts/Personal-Repo/GetForestFunctionalLevel.ps1) | Delete | Forest level | Covered by the AD report |
| [Get-DomainReplicationStatus.ps1](Scripts/Personal-Repo/Get-DomainReplicationStatus.ps1) | Delete | Replication status, errors and events (RMM-style, custom fields) | Covered by the AD report |
| [GetComputerLastLogonDate-AndMoveToOU.ps1](Scripts/Personal-Repo/GetComputerLastLogonDate-AndMoveToOU.ps1) | Ask | Finds disabled and stale computers; moves and disables them | Possible stale-object clean-up tool. General AD hygiene |
| [GetADDevices-Name_Version_Timestamp.ps1](Scripts/Personal-Repo/GetADDevices-Name_Version_Timestamp.ps1) | Delete | Computers with OS, version and last logon | Covered by the AD report |
| [GetComputerLastLogonDate.ps1](Scripts/Personal-Repo/GetComputerLastLogonDate.ps1) | Delete | Computers by last logon | Covered by the AD report |
| [GetADUsers-LastLockOutDate.ps1](Scripts/Personal-Repo/GetADUsers-LastLockOutDate.ps1) | Delete | Users by lockout time | Covered by the AD report |
| [GetPasswordLastSetDate.ps1](Scripts/Personal-Repo/GetPasswordLastSetDate.ps1) | Delete | Users by password last set | Covered by the AD report |
| [GetADUsers-LastPasswordSetDate.ps1](Scripts/Personal-Repo/GetADUsers-LastPasswordSetDate.ps1) | Delete | Users in an OU by password last set, to CSV | Covered by the AD report |
| [Get-AllActiveADUsers.ps1](Scripts/Personal-Repo/Get-AllActiveADUsers.ps1) | Delete | All enabled users to CSV | Covered by the AD report |
| [GetADUsers-All-CSVExport.ps1](Scripts/Personal-Repo/GetADUsers-All-CSVExport.ps1) | Delete | All users with password flags to CSV | Covered by the AD report |
| [DisablePasswordNeverExpiresOU.ps1](Scripts/Personal-Repo/DisablePasswordNeverExpiresOU.ps1) | Ask | Clears Password never expires in an OU | General user admin |
| [GetADUsers-ChangePassword_SetChangeOnLogin.ps1](Scripts/Personal-Repo/GetADUsers-ChangePassword_SetChangeOnLogin.ps1) | Ask | Clears Password never expires, resets passwords, sets change at next logon | General user admin. Had a password in the file (removed) |
| [GetAllADUsers-ChangePassword_SetChangeOnLogin.ps1](Scripts/Personal-Repo/GetAllADUsers-ChangePassword_SetChangeOnLogin.ps1) | Ask | Same, marked not complete | Duplicate of the one above. Had a password and a client OU in the file (removed) |
| [ChangeToNewUPNSuffix.ps1](Scripts/Personal-Repo/ChangeToNewUPNSuffix.ps1) | Ask | Changes users' UPN suffix in an OU | General / hybrid identity prep |
| [RemoveOrAddConnect_HomeFolderAttributesInAD.ps1](Scripts/Personal-Repo/RemoveOrAddConnect_HomeFolderAttributesInAD.ps1) | Ask | Sets or clears home folder attributes in an OU | General user admin |
| [CreateFoldersFrom-sAMAccountName.ps1](Scripts/Personal-Repo/CreateFoldersFrom-sAMAccountName.ps1) | Ask | Creates a folder per user on a share | File server work |
| [Import-MatchADAttributes-EmployeeID.ps1](Scripts/Personal-Repo/Import-MatchADAttributes-EmployeeID.ps1) | Ask | Imports employee IDs from CSV with fuzzy name matching | General user admin |
| [Add sMSA account to AD.ps1](Scripts/Personal-Repo/Add%20sMSA%20account%20to%20AD.ps1) | Ask | Creates and installs a standalone managed service account | A gMSA tool would replace it |
| [Get-LDAPQuery_User_Group.ps1](Scripts/Personal-Repo/Get-LDAPQuery_User_Group.ps1) | Keep outside | User and group lookups over ADSI from a member server without RSAT | The toolkit needs RSAT |

## Screenshots

(None yet.)

## GPO baselines

32 GPMC HTML reports from one client build, in `GPO-Reports/`. Scrubbed before commit: client name,
domain, server and account names, IP ranges, SSID, CA name and GPO IDs replaced with placeholders
(`ClientX`, `clientx.local`, `DC01`, `192.0.2.0/24` and so on); converted from UTF-16 to UTF-8.

Only the **settings** are the baseline. Links, delegation, security filtering, WMI filters and owners in
the reports are that client's and are ignored (see `CLAUDE.md`). **Parameters** are the values asked for
at build time. **Kinds** says which part of the GPO holds the settings, which decides how a tool writes
them: Admin templates (registry policy), Security (security template: security options, user rights,
restricted groups, services, file system, audit policy), Preferences (registry or service items),
Firewall, Wireless, Software install, Public key.

All 32 are **To do**.

| GPO | Kinds | What it sets | Parameters | Notes |
| --- | --- | --- | --- | --- |
| Group Policy Processing | Admin templates | Registry and security policy processed even if unchanged; refresh 15 min + 30 random (computers and DCs); 60 s startup wait; wait for network at startup | refresh and wait times (defaults as here) | |
| Network - Prefer IPv4 over IPv6 | Preferences | `Tcpip6\Parameters\DisabledComponents` = 0x20 | | Microsoft-supported value |
| Network - Disable NCSI | Admin templates | NCSI: use global DNS | | Name says "disable" but it only sets global DNS; rename or add the setting |
| Network - Time Synchronization | Admin templates, Preferences | NTP client: server, type NT5DS, poll 1024; location provider on; `tzautoupdate` Start = 3 | NTP server | With type NT5DS the server name is ignored (domain hierarchy). Nothing here sets the PDC's external source |
| Devices - Power Profile (Workstations) | Admin templates | High Performance plan; no sleep, standby or hibernate; sleep and hibernate hidden | | Meant for desktops (was WMI-filtered) |
| Printer Deployment - Point and Print Restrictions | Admin templates, Preferences | Approved print servers; no warning or elevation prompts; `RestrictDriverInstallationToAdministrators` = 0 | print server FQDNs | No prompts plus 0 is the combination KB5005652 warns about; review before it becomes the baseline |
| Remote Desktop - Devices (Default) | Security, Admin templates | RDP allowed; NLA, SSL layer, high encryption, secure RPC, always prompt; no saved passwords; client server auth required; 2 connections; 1 h idle limit; COM, LPT, smart card, PnP and video redirection off; user right and Remote Desktop Users group set to an admin group | group allowed to RDP | Restricted Groups replaces the group's members. Domain Admins on workstations breaks tiering; pick the group per run |
| Remote Desktop - Servers (Default) | Security, Admin templates | Same settings as Devices | group allowed to RDP | Identical settings to Devices: one baseline with two names, or one GPO |
| Security - DUO Desktop (Laptops - See WMI Filtering) | Preferences | Duo Device Health auto-updater disabled; `DuoDesktopUpdateService` stopped and disabled | | Meant for laptops |
| Security - DUO Standards (Devices) | Admin templates | Duo logon: auto push off; offline access for elevation on; Duo at logon and UAC | | Needs the Duo ADMX in the central store |
| Security - DUO Standards (Servers) | Admin templates, Preferences | Duo logon: auto push off; offline access off; Duo at logon and UAC; same values also as registry items | | Registry items repeat the template settings; keep one |
| Software - DUO Rollout | Software install | Assigns Duo Authentication for Windows Logon x64 (4.3) | installer path (UNC), version | Generalize: installer from a share chosen at build time, not NETLOGON. Keep Duo keys out of a customized MSI that every user can read |
| Security - Disable AutoPlay | Admin templates | AutoRun: no autorun commands; AutoPlay off on all drives | | |
| Security - Disable Print Spooler | Security | Print Spooler service disabled | | For DCs and servers that don't print |
| Security - Domain Auditing (DC's) | Security (audit) | Advanced audit: account logon, account management, DS access, logon/logoff, policy change | | |
| Security - Domain Auditing (File Servers) | Security (audit) | Advanced audit: account logon and management, logon/logoff, object access (file share, file system, registry, SAM, WFP), policy change, system | | |
| Security - Domain Auditing (Devices) | none | Empty | | Drop, or define device auditing |
| Security - Enforce UAC | Security | UAC: admin approval mode (built-in admin too), credentials on secure desktop for admins and users, detect installs | | |
| Security - ClientX Disclaimer | Security | Logon banner title and text | organization name, banner text | Text mentions CUI; make the text a parameter with a default |
| Security - Kerberos Encryption | Security | Kerberos: AES256 and future types only (DES, RC4 and AES128 off) | | Check for accounts without AES keys before applying |
| Security - LDAPS Hardening (DC's) | Security | LDAP server signing required; channel binding Always | | |
| Security - LDAPS Hardening (Devices) | Security | LDAP client signing required | | |
| Security - NTLM Hardening | Security | LAN Manager level: NTLMv2 only, refuse LM and NTLM | | |
| Security - PKI - CA Infrasturcture | Public key | Certificate auto-enrollment on (renew, update, remove revoked); the CA's root in Trusted Root | CA root certificate | Certificate itself is not in the report; read from the environment's CA |
| Security - Powershell Script Block Logging | Security, Admin templates, Preferences | Module logging `*`; script block logging with invocation events; command line in process creation events; profile.ps1 permissions; Windows PowerShell log 20 MB | | Add PowerShell 7 (PowerShell Core) logging and transcription. Size the `PowerShell/Operational` log too (4104 lands there). `%UserProfile%` file entry has no effect in a computer GPO |
| Security - Removable Drive Restrictions | Admin templates (user) | All removable storage: deny all access = Disabled | | As set, this allows access; the deny GPO it pairs with is not in the set |
| Security - Rename and Disable Local Accounts | Security | Administrator and Guest disabled and renamed | new Administrator and Guest names | Linked at the domain root this also renames and disables the domain Administrator; decide per run |
| Security - SMB Hardening | Security, Preferences | SMB signing always (client and server); secure channel sign or encrypt always; SMB1 off (`SMB1` = 0, `mrxsmb10` Start = 4, workstation dependencies without MRxSmb10) | | |
| Security - Screen Timeout | Admin templates (user) | Screen saver on, `scrnsave.scr`, password protected, 900 s | timeout | |
| Windows Firewall - Devices (Default) | Firewall, Admin templates | All profiles on, inbound block, outbound allow, log dropped and allowed (32 MB); local rules not merged; notifications off; inbound RDP (TCP and UDP) and ICMP from one range | management range | Rules are "allow if secure" (require authentication) with no connection security rules; check before reuse |
| Windows Firewall - Servers (Default) | Firewall, Admin templates | As Devices, but local rules still merge and notifications are not set | management range | As Devices |
| Wireless - ClientX-Production | Wireless | WPA2-Enterprise AES, 802.1X computer authentication, certificate (EAP-TLS), server validation against the CA, PMK caching | SSID, CA, RADIUS server names | |
