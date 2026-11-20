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

### Active Directory (`ad`)

| Tool | Id | Kind | What it does |
| --- | --- | --- | --- |
| OU Layout | `ou-layout` | Report + Change | Create the standard OU tree under an organization OU (Computers, Servers, Users, and whatever else the standard needs, plus a GPO Test OU), protected from accidental deletion. Optionally point new computers and users at those OUs (`redircmp` / `redirusr`). Shows what exists and creates only what's missing |
| Privileged Groups | `ad-privileged` | Report | Members of Domain, Enterprise and Schema Admins, Administrators, Account/Server/Backup/Print Operators, DnsAdmins, and objects with `adminCount` set. Nested members resolved |
| Stale and Risky Accounts | `ad-stale` | Report | Users and computers not signed in for N days, disabled but still in groups, password never expires, no password required, reversible encryption, old `krbtgt` password |

### Readiness and health (`health`)

| Tool | Id | Kind | What it does |
| --- | --- | --- | --- |
| Hardening Readiness | `ready` | Report | Run before the baselines that can break things: accounts and services without AES keys (Kerberos Encryption), unsigned or non-channel-bound LDAP binds (DC events 2889, 3039; LDAPS Hardening), NTLMv1 and LM logons (4624; NTLM Hardening), SMB1 clients (SMB Hardening). Says per baseline whether it is safe to apply |
| DC Health | `dc-health` | Report | Each DC: services (NTDS, DNS, Netlogon, KDC, W32Time, DFSR), SYSVOL and NETLOGON shared, DFSR SYSVOL state, FSMO holders, time source (the PDC on an external source, the others on the hierarchy), DNS, free disk space, and PowerShell 5.1 and 7 logging policy in effect |
| Replication | `dc-replication` | Report | Replication partners, last success, failures and their error text, per DC and naming context |
| DC Security Events | `dc-events` | Report | Ready-made event searches across the DCs: lockouts (4740), failed sign-ins (4625, by account and source), privileged group changes (4728, 4732, 4756), audit policy changes (4719), log cleared (1102), new services (7045). Events read into named fields (from `Get-EventIDHashTables.ps1`) |

### Toolkit (`kit`)

| Tool | Id | Kind | What it does |
| --- | --- | --- | --- |
| Session and Prerequisite Check | `session-info` | Report | PowerShell version, elevated or not, RSAT modules, domain, which DC it's talking to, the signed-in account and its admin groups |
| Settings | (menu) | | Defaults for parameters (NTP server, management range, organization name), export folder, and so on |

## Order of work

1. Core and launcher (copied from M365-Tools and adapted), `session-info`.
2. The baseline file format, and `gpo-build` and `gpo-compare` for the easy kinds (template settings,
   registry preferences, security options, user rights, audit, services). About 20 of the 32 baselines.
3. `gpo-scope`, `gpo-wmi`, `gpo-admx`, `gpo-inventory`.
4. Firewall baselines, then the hard kinds: wireless, software installation, certificate trust.
5. `ou-layout`, `ready`, then the health and AD reports.
6. `gpo-capture`.

## Open questions

- **OU standard:** the reports show Computers, Servers and Users under the organization OU. Is that the
  whole standard, or are there more OUs (groups, service accounts, admin or tier OUs, disabled objects)?
- **Where it runs:** on a DC, or also from a management server or workstation with RSAT? Both work for
  everything except `ou-layout` redirection (needs a domain admin), but it changes how DCs are reached.
