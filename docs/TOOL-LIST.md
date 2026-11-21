# Draft tool list (for review)

Status: draft for Cliff to review. Nothing here is built yet. Ids, names and sections can all change.

## How baselines work

- Each GPO report in `Legacy/GPO-Reports/` becomes one **baseline file** in `Nutmeg.AD/Baselines/`: the
  GPO's settings, readable and diffable, with placeholders for the values that change per environment
  (`{NtpServer}`, `{ManagementRange}`, `{OrgName}` and so on) and a default for each.
- Building from a baseline makes a **new, ordinary GPO**, written setting by setting. It is not imported
  from a backup, and it is edited in GPMC afterwards like any other GPO.
- Each build ends with its own per-GPO step, because no two GPOs are set up the same way:
  links, security filtering, exclusions, WMI filter and delegation are chosen there, one GPO at a time.
- Settings with no GroupPolicy cmdlet (wireless, software installation, certificate trust) need their
  own writers. They come last, after everything else works.

## Sections

Same idea as the M365 toolkit's admin centers: a section, then the task, then the tool.

### Group Policy (`gpo`)

| Tool | Id | Kind | What it does |
| --- | --- | --- | --- |
| Build GPOs from Baselines | `gpo-build` | Report + Change | Pick one or several baselines. For each one: answer its parameters (defaults offered), name the GPO (baseline name by default), create it and write its settings. Asks first; `-WhatIf`. If a GPO by that name exists, it stops and offers Compare instead of overwriting. Then the per-GPO step: link, filter, delegate (`gpo-scope`), or skip and do it later |
| Links, Filtering and Delegation | `gpo-scope` | Report + Change | One GPO at a time: link or unlink OUs (order, enforced, enabled), security filtering (add groups or computers, take out Authenticated Users), exclusions (deny apply for one computer, group or user), WMI filter, delegation (edit, read). Shows the current state first |
| Compare GPOs with Baselines | `gpo-compare` | Report | One GPO or all of them against their baseline: missing settings, different values, extra settings, and parameters that weren't filled in. This is the check that a client still matches the standard |
| WMI Filters | `gpo-wmi` | Report + Change | List the domain's WMI filters and create standard ones from a short library: desktops, laptops (chassis type), servers, DCs, workstations by OS |
| ADMX Central Store | `gpo-admx` | Report + Change | Check `SYSVOL\Policies\PolicyDefinitions`: whether it exists, and whether it has the templates the baselines need (Windows, PowerShell Core, Duo). Create it and copy templates in, asking first. The Duo and PowerShell 7 baselines need this before they can be built |
| GPO Inventory | `gpo-inventory` | Report | Every GPO: links, status, filtering, WMI filter, last change, and which baseline it matches. Flags empty, unlinked, disabled and "applies to nobody" GPOs. Exports the GPMC HTML report per GPO for documentation |
| Capture a GPO as a Baseline | `gpo-capture` | Report | Read a live GPO and write a new baseline file from its settings, turning the values you pick into parameters. This is how new baselines get added after a new client build. Writes only the file, never the domain |

### Reports (`report`)

| Tool | Id | Kind | What it does |
| --- | --- | --- | --- |
| AD Health and Inventory Report | `ad-report` | Report | Cliff's AD-Advanced-Report (v4.5), kept whole: one HTML report with executive summary and findings JSON, covering DC health, replication, sites and DNS, users, groups, privileged access, security, computers and LAPS, OUs and GPOs. The tool asks for client name, logo and folder (and the day thresholds) through the core, then runs the script in its own process with `-NoPrompt`. Replaces the separate DC health, replication, privileged groups, stale accounts and DC events tools in the first draft |

### Active Directory (`ad`)

| Tool | Id | Kind | What it does |
| --- | --- | --- | --- |
| OU Layout | `ou-layout` | Report + Change | Create Cliff's standard tree: one organization OU directly under the domain root (`OU=<CompanyName>,DC=...`), with the standard OUs below it (Devices, Security Groups, Service Accounts, Users and the rest of the list, still to be confirmed), protected from accidental deletion. Optionally point new computers and users at those OUs (`redircmp` / `redirusr`). Shows what exists and creates only what's missing |
| Groups and Members | `ad-groups` | Report | Find groups by part of a name; members of one or all of them, nested resolved; a privileged view (Domain Admins and the other built-in admin groups, with each member's groups). From the group export scripts |

### Readiness (`ready`)

| Tool | Id | Kind | What it does |
| --- | --- | --- | --- |
| Hardening Readiness | `ready` | Report | Run before the baselines that can break things, per DC or domain: accounts without AES keys (Kerberos Encryption), unsigned or non-channel-bound LDAP binds (events 2889, 3039; LDAPS Hardening), NTLMv1 and LM logons (4624; NTLM Hardening), SMB1 clients (SMB Hardening), and SSL/TLS on each DC (from Audit-SslTlsCiphersAndProtocols; SCHANNEL Hardening). Says per baseline whether it is safe to apply |
| Kerberos AES for Accounts | `ready-aes` | Report + Change | Sets AES encryption types on the accounts `ready` found without them (from Enable-UserKerberosEncryption). Asks first; `-WhatIf` |

### Toolkit (`kit`)

| Tool | Id | Kind | What it does |
| --- | --- | --- | --- |
| Session and Prerequisite Check | `session-info` | Report | PowerShell version, elevated or not, RSAT modules, domain, which DC it's talking to, the signed-in account and its admin groups |
| Settings | (menu) | | Defaults for parameters (NTP server, management range, organization name), export folder, and so on |

## Order of work

1. Core and launcher (copied from M365-Tools and adapted), `session-info`. **Done in 0.1.0.**
2. The baseline file format, and `gpo-build` and `gpo-compare` for the easy kinds (template settings,
   registry preferences, security options, user rights, audit, services). About 20 of the 32 baselines.
   The format includes a control-tag field on every setting from the start (see Compliance profiles).
3. `gpo-scope`, `gpo-wmi`, `gpo-admx`, `gpo-inventory`.
4. Firewall baselines, then the hard kinds: wireless, software installation, certificate trust.
5. `ad-report` (wrapping the existing script), `ou-layout`, `ready` and `ready-aes`, `ad-groups`.
6. The AD admin tools.
7. `gpo-capture`.
8. Compliance profiles (next project, to revisit with Cliff): see below.
9. New Forest Build (planned with Cliff, Nov 2026): see below. Built last, because it runs the tools above.

## New Forest Build (planned)

One guarded, mostly unattended run for the **first DC of a brand-new forest**: from a freshly installed
Windows Server to a promoted, structured and baselined domain. It only runs on a workgroup server
where no domain of that name answers; on an existing domain the individual tools are used instead.

Each step calls the same tool a technician would run by hand, so one set of code and tests covers both.
Every change tool therefore must run without prompts when given its parameters (a rule from step 2 on).

Phases, with a reboot where marked:

0. **Prepare the server** (workgroup only): pick the network adapter (if there are several); static IP
   (default: the current DHCP subnet with `.50`, Cliff's standard for DCs; any address can be typed),
   prefix and gateway from the current lease, pre-promotion DNS (gateway or an external resolver);
   check nothing answers on the new IP; computer name; time zone. The IP change goes last and asks
   nothing after it, because it drops an RDP session to the DHCP address: show the new address, then
   restart on a countdown. IPv6 stays on (Microsoft doesn't support disabling it on DCs). *Reboot.*
1. **Promote:** install AD DS, DNS and GPMC; `Install-ADDSForest`. *Reboot.*
2. **After promotion:** DNS client to its own IP then `127.0.0.1`; DNS forwarders, scavenging, reverse
   zone; sites and subnets; the PDC's external time source; Recycle Bin; KDS root key; PowerShell 7;
   ADMX central store.
3. **Structure:** `ou-layout` from `Data/OuStandard.csv`, new computers and users redirected.
4. **GPOs:** every baseline built and linked per `Data/GpoDefaultLinks.csv`, standard filtering. Client
   exceptions are added afterwards with the individual tools.
5. **Report:** `session-info`, `ad-report`, and a summary of every step and its result.

Design points:
- **Answer file** per client (domain, NetBIOS, company OU, IPs, NTP source, banner text and so on); the
  repo holds only a template. Reviewed in a dry run of the whole plan before anything changes.
- **DSRM password** typed once at the start, held in memory only, never written anywhere.
- **Resumable:** a state file records each finished step; after a reboot or a failure, the run picks up
  where it stopped and skips what is done.
- **One confirmation:** the domain name typed once approves the whole plan (a "plan approved" mode in
  `Confirm-NmChange`); every change still goes to run history.
- **Day-one hardening:** Kerberos AES-only, NTLMv2, LDAP signing and SCHANNEL apply from the start; the
  summary warns that legacy devices joining later need `ready`.

Open: first DC only, or also a second DC into the domain it just built; answer file or up-front
questions (wizard); adapter settings beyond IP, gateway and DNS (rename, power management, DNS
registration).

## Compliance profiles (next project)

Agreed in principle (Nov 2026); to revisit once the Nutmeg baseline is built. Not started.

- **Why:** onboarding a forest for a regulated client (a healthcare practice under HIPAA, a credit union
  under NCUA, a contractor with CUI under NIST 800-171 / CMMC) should start from a profile that meets
  that framework, not just the Nutmeg Standard.
- **Shape:** the Nutmeg Standard baseline stays the base layer. Each setting carries control tags
  (for example screen timeout: HIPAA 164.312(a)(2)(iii), NIST 800-53 AC-11, 800-171 3.1.10). A
  compliance profile is an overlay that adds GPOs and tightens values; it is picked in `gpo-build`, and
  links and delegation are still chosen per GPO. A compliance report lists each control, the setting
  that covers it, its live state (`gpo-compare`), and the controls GPO can't cover, marked outside the
  toolkit.
- **Settings sources:** HIPAA, NCUA/FFIEC and NIST 800-53/171 are outcome-based and name no Windows
  settings. Settings come from technical benchmarks: DISA STIG (public domain, GPO packages), Microsoft
  Security Baselines (free; downloaded at run time, not committed), CIS Benchmarks (cross-reference by
  section number only; their GPOs and text are licensed and not copied in).
- **Likely additions** to the Standard for most profiles: BitLocker, Windows LAPS, password and lockout
  policy, Credential Guard and LSA protection, WDigest off, LLMNR and NetBIOS off, Defender ASR rules,
  event log size and retention, SMB encryption.
- **Open when we revisit:** which framework first (HIPAA, NIST 800-171/CMMC, FFIEC/NCUA); which
  benchmark to build from (proposed: DISA STIG plus Microsoft, CIS as cross-reference); the research
  write-up per framework with sources. Check NCUA's current guidance then: FFIEC retired its
  Cybersecurity Assessment Tool in 2025 and pointed to NIST CSF 2.0.

## New baselines from the scripts

- **Security - SCHANNEL Hardening**: SSL 2.0/3.0 and TLS 1.0/1.1 off (from CreateGPO-SSL_TLS-Disable).
- **Audit policy, per role** (decided): Domain Auditing (DCs), (Servers) and (Devices), each starting
  from the Huntress list in Update-AuditPol-HuntressDefaults as the minimum, with the role's extra
  subcategories from the existing GPOs on top (File Servers becomes Servers, or stays as its own role).
  Process Creation is turned on wherever the PowerShell logging GPO applies, so command lines are logged.

### AD admin (`admin`) (in scope, decided)

Day-to-day AD work from the personal repository. Every one is a change tool: asks first, `-WhatIf`,
a `Result` per object, run history; forest- or domain-wide changes need the domain name typed.

| Tool | Id | Kind | What it does |
| --- | --- | --- | --- |
| FSMO Roles | `dc-fsmo` | Report + Change | Show the role holders; move one or all roles to another DC (from MigrateFSMOtoNewServer). Seizing is not offered |
| Functional Levels | `ad-levels` | Report + Change | Show schema version, domain and forest levels and the highest each can go to; raise the domain or forest level. Schema upgrades (adprep) stay manual |
| Sort New Computers | `ad-sort-computers` | Report + Change | New computers all land in `Devices/Workstations` (redircmp has one target). Lists computers there running Windows Server and moves them to `Devices/Member Servers`; servers outside Member Servers are flagged by `ad-report` too. Optional: pre-create a server's computer object in Member Servers before it joins |
| Stale Computers | `ad-stale-computers` | Report + Change | Computers not signed in for N days or already disabled; disable and move them to a chosen OU, with an exclude list (from GetComputerLastLogonDate-AndMoveToOU) |
| Password Never Expires | `ad-pwd-never-expires` | Report + Change | Accounts in an OU with Password never expires; clear the flag, with exclusions. Service accounts are listed separately and left alone unless picked |
| Bulk Password Reset | `ad-pwd-reset` | Report + Change | Reset passwords and set change at next logon for the users in an OU, with exclusions. The password is typed at run time, never stored |
| UPN Suffix | `ad-upn` | Report + Change | List UPN suffixes and who uses them; change users in an OU to another suffix |
| Home Folders | `ad-home-folders` | Report + Change | Set or clear users' home drive and folder attributes in an OU, and optionally create each user's folder on the share with the right permissions |
| Managed Service Accounts | `ad-gmsa` | Report + Change | List service accounts; create a gMSA (and the KDS root key if missing) for named servers. Replaces the sMSA script |

## Open questions

- **OU standard:** done. Agreed in the OU Standard doc (claude.ai artifact) and copied to
  `Nutmeg.AD/Data/OuStandard.csv` (`ou-layout`) and `Nutmeg.AD/Data/GpoDefaultLinks.csv` (`gpo-build`'s
  default links, confirmed or changed on every run). Paths are relative to the organization OU unless
  the parent is the domain root.

## Decided

- Runs on a DC only (elevated, as a domain admin). Other DCs are reached from there.
- Audit policy per role.
- SCHANNEL Hardening is in, to Microsoft's current guidance: `docs/baselines/Security-SCHANNEL-Hardening.md`.
- Firewall GPOs always merge local rules. Time Synchronization links at Devices only.
- Disabled objects live directly under the domain root (Z-Disabled Users, Z-Disabled Computers), outside the organization OU and the Entra Connect sync scope; Users/Z-Disabled Users-SharedMailboxes stays in scope for shared mailboxes. Admin accounts stay in Users/Admin Accounts.
- General AD admin is in, except the employee ID import.
