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

(None yet.)

## Screenshots

(None yet.)

## GPO baselines

(None yet.)
