# DomainController-Security

The Nutmeg AD Toolkit (working name `Nutmeg.AD`): one menu-driven PowerShell module for Active Directory
domain controller onboarding after the DC is built by hand: OU and tier layout, GPO baselines,
reports and health checks. Hardening (DC and domain) comes from the GPO baselines in
`Legacy/GPO-Reports/`. Building a DC (installing AD DS, creating the forest, promoting
DCs) stays manual and is not part of the toolkit. It follows the same pattern as the Nutmeg M365
Toolkit (M365-Tools): a shared core for menus, logging, safety prompts, exports and settings, and one
file per tool.

Status: intake. No module code yet. See `Legacy/INDEX.md` for what is in and where it goes, and `CLAUDE.md` for the rules (PowerShell 7, M365-Tools as the pattern).

## Intake

Drop source material under `Legacy/` (see `Legacy/README.md`):

| Folder | What goes there |
| --- | --- |
| `Legacy/Scripts/` | existing scripts, as they are (subfolders are fine) |
| `Legacy/Screenshots/` | screenshots of settings or steps that should become new scripts |
| `Legacy/GPO-Reports/` | GPO HTML reports (`Get-GPOReport -ReportType Html`, or saved from GPMC) |

Nothing in `Legacy/` is loaded by the toolkit. `Legacy/INDEX.md` (built once the scripts are in) will
track each item: ported to which tool, to do, deleted, or kept outside.
