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
| OU Layout | `ou-layout` | Report + Change | Create the standard OU tree under an organization OU (Computers, Servers, Users, and whatever else the standard needs, plus a GPO Test OU), protected from accidental deletion. Optionally point new computers and users at those OUs (`redircmp` / `redirusr`). Shows what exists and creates only what's missing |
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

1. Core and launcher (copied from M365-Tools and adapted), `session-info`.
2. The baseline file format, and `gpo-build` and `gpo-compare` for the easy kinds (template settings,
   registry preferences, security options, user rights, audit, services). About 20 of the 32 baselines.
3. `gpo-scope`, `gpo-wmi`, `gpo-admx`, `gpo-inventory`.
4. Firewall baselines, then the hard kinds: wireless, software installation, certificate trust.
5. `ad-report` (wrapping the existing script), `ou-layout`, `ready` and `ready-aes`, `ad-groups`.
6. `gpo-capture`.

## New baselines from the scripts

- **Security - SCHANNEL Hardening**: SSL 2.0/3.0 and TLS 1.0/1.1 off (from CreateGPO-SSL_TLS-Disable).
- **Audit policy (Huntress)**: the 59 subcategories in Update-AuditPol-HuntressDefaults, as a GPO. It
  overlaps the three Domain Auditing GPOs and turns Process Creation off, which the PowerShell logging
  GPO needs on. Decide: one audit baseline for everything, or per role (DCs, servers, devices) with the
  Huntress list as the floor.

## Maybe (general AD admin)

From the personal repository. In scope only if the toolkit is also for day-to-day AD work, not just
onboarding: FSMO transfer, raising domain and forest levels, stale computer clean-up (disable and move),
password never expires and org-wide password resets, UPN suffix change, home folder attributes and
folders, employee ID import, managed service accounts (gMSA).

## Open questions

- **OU standard:** the reports show Computers, Servers and Users under the organization OU. Is that the
  whole standard, or are there more OUs (groups, service accounts, admin or tier OUs, disabled objects)?
- **Where it runs:** on a DC, or also from a management server or workstation with RSAT? Both work for
  everything except `ou-layout` redirection (needs a domain admin), but it changes how DCs are reached.
