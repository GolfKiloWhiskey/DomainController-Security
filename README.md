# DomainController-Security

The Nutmeg AD Toolkit (`Nutmeg.AD`): one menu-driven PowerShell module for Active Directory domain
controller onboarding after the DC is built by hand: OU layout, GPO baselines, readiness checks,
reports and day-to-day AD admin. Hardening (DC and domain) comes from the GPO baselines. Building a DC
(installing AD DS, creating the forest, promoting DCs) stays manual and is not part of the toolkit.

It follows the Nutmeg M365 Toolkit's pattern (M365-Tools): one core for menus, logging, safety
prompts, exports and settings, and one file per tool. The plan is `docs/TOOL-LIST.md`.

## Get it onto a server

Copy `Get-NutmegAD.ps1` to the server (or paste it into Windows PowerShell as administrator) and run:

```powershell
.\Get-NutmegAD.ps1
```

It asks for a GitHub token (fine-grained, this repository only, Contents: Read-only; typed hidden and
never saved), downloads `main` into `C:\Tools\DomainController-Security`, keeps any copy already there
as `.previous`, and unblocks the files. It installs PowerShell 7 if it is missing (the current LTS,
Microsoft's signed MSI, Microsoft Update on; no question, `-SkipPowerShell7` leaves it out). Then it
changes to that folder and opens the window: the New Forest Build on a workgroup server, the toolkit
on a domain-joined server or DC. `-Console` uses the console instead, `-Branch <name>` gets a branch
still in review, `-Path` puts it elsewhere, `-NoStart` only downloads. Run it again to update.

## Run it

On a domain controller, as a domain admin:

```powershell
.\Start-NutmegAD.ps1
```

- Checks the server first: a fresh workgroup server, or one with a New Forest Build in progress,
  opens the build; a DC or domain member opens the toolkit. `-NewForest` or `-Toolkit` says which.
- When the build finishes it offers to open the toolkit (Yes by default): the build closes and the
  toolkit opens, in PowerShell 7 when it is installed.
- Opens the window. `-Console` opens the console menu instead. In PowerShell 7 the window has the
  Windows 11 look, light or dark as Windows is set (Settings > Window > Window look: Windows 11 or
  Classic); Windows PowerShell 5.1 keeps the classic light look. Colours are Nutmeg's, from the logo.
- The layout is yours: the menu button (top left) hides the side panels, the edges between areas can
  be dragged, the options fold into one line after Run, and Output opens as its own pane. It is kept
  for next time; right-click the menu button to reset it.
- Runs in PowerShell 7 whenever it is installed: started in Windows PowerShell 5.1, it moves to 7
  without asking. Not installed: it offers to install the current LTS release (Microsoft's signed
  MSI, with Microsoft Update on), or carries on in 5.1.
- Not elevated: offers to start again as administrator.
- `-Stay` stays where it was started: no move to PowerShell 7, no offer to elevate.

**The window:** the same tools as the console menu: areas on the left,
each tool's options as a form (or **Guided...** for its own questions), results as cards or a table
with filter, export and row details. Questions come in the console's order as clean dialogs (no
console text: notes, tables and the suggested answer), changes are approved in one approval dialog,
and long steps run in the background so the window keeps responding. Logs and run history are the
same as the console's. The header shows the domain and the DC (click it for
**Domain and DC**) and which modules are loaded; the cog opens Settings. The normal window leaves the
New Forest Build out; `-NewForest` opens the window on the build alone. New tools reach the window
only after they pass QA in the console.

**A brand-new forest:** on a freshly installed Windows Server in a workgroup, `Get-NutmegAD.ps1`
opens it in the window, or run `.\Start-NutmegAD.ps1 -NewForest` (add `-Console` for the
console). It always runs in Windows PowerShell 5.1. It checks the server, asks its questions once, shows the plan, and
then sets the IP and name, installs AD DS and creates the forest, carrying on by itself after each
restart (sign in as an administrator and it reopens, in the window if it started there). It refuses to run on a domain-joined server or
for a domain that already answers. See `docs/NEW-FOREST-TESTING.md`.

On a domain-joined server or DC, the toolkit loads `ActiveDirectory` and reads the domain and DC
automatically on start so **Domain and DC** shows them right away (`GroupPolicy` loads when a GPO
tool needs it). **Domain and DC** in the main menu shows the domain, its levels and the PDC, and can
point the toolkit at another DC.

Logs and run history: `C:\Temp\NutmegAD` (a New Forest Build keeps one log from `Get-NutmegAD.ps1`
to the finished DC, across its restarts). Exports: `C:\Temp`. Settings (per Windows user):
`%APPDATA%\NutmegAD\Settings.json`.

## Tools

| Area | Section | Tool | Id | Kind |
| --- | --- | --- | --- | --- |
| New forest build | First DC | New Forest Build (first DC): pre-flight, questions, static IP, name, AD DS, promotion, then on to the toolkit; phases 2 to 5 to come | `new-forest` | Change |
| Group Policy | Baselines | Build GPOs from Baselines: pick baselines, answer their parameters, each becomes a new GPO (not linked; an existing GPO is never overwritten) | `gpo-build` | Report + Change |
| Group Policy | Baselines | Compare GPOs with Baselines: missing, different, extra and not-filled settings, per GPO | `gpo-compare` | Report |
| Group Policy | Baselines | Align GPOs with Baselines: put a GPO back to its baseline (only its settings, or reset exactly), backed up first; from Compare's cards too | `gpo-align` | Report + Change |
| Group Policy | Baselines | Restore GPO from Backup: put a GPO back from a backup the toolkit made (its current state backed up first) | `gpo-restore` | Report + Change |
| Reports | Reports | DC Report: a report per DC (HTML and PDF): roles, DNS order, replication, SYSVOL, health, dcdiag | `dc-report` | Report |
| Toolkit | Diagnostics | Session and Prerequisite Check (PowerShell, elevation, DC, modules, domain, admin groups, folders) | `session-info` | Report |

The rest are listed in `docs/TOOL-LIST.md` and arrive in the order given there.

**Baselines** (`Nutmeg.AD/Baselines/`, one `.psd1` file each, format in `docs/baselines/FORMAT.md`):
Group Policy Processing, Network - Prefer IPv4 over IPv6, Network - Disable NCSI, Time Synchronization,
Power Profile (Workstations), Disable AutoPlay, Disable Print Spooler, Domain Auditing (DC's),
Enforce UAC, Kerberos Encryption, LDAPS Hardening (DC's) and (Devices), NTLM Hardening, Screen Timeout.
More follow as they are converted.

## Run a tool without the menu

```powershell
Import-Module .\Nutmeg.AD\Nutmeg.AD.psd1
Invoke-NmTool -Id session-info -NoMenu
```

`Get-NmTool` lists every tool and its Id.

## Layout

```
Start-NutmegAD.ps1          launcher
Get-NutmegAD.ps1            downloads or updates the toolkit on a server (standalone, not loaded by the module)
Nutmeg.AD/
  Nutmeg.AD.psd1 / .psm1    module manifest and loader
  Core/                     domain session, modules, logging, menus, exports, safety, settings, registry, launcher,
                            PowerShell 7, the server and the build state (New Forest Build)
  Tools/<Category>/         one file per tool; _ToolTemplate.ps1 shows the format
  Baselines/                one .psd1 file per GPO baseline (docs/baselines/FORMAT.md)
  Data/                     OuStandard.csv, GpoDefaultLinks.csv
Tests/Invoke-CoreTests.ps1  core tests (no domain or AD module needed)
Tests/Invoke-BuildTests.ps1 New Forest Build tests (a fake fresh server)
Tests/Invoke-GetTests.ps1   Get-NutmegAD.ps1 tests (fake GitHub zips)
Tests/Invoke-GpoTests.ps1   baselines, gpo-build and gpo-compare (fake GroupPolicy cmdlets, a temp SYSVOL)
Tests/Invoke-AllTests.ps1   runs every test file and prints a total
Legacy/                     source material: scripts, GPO reports, screenshots; INDEX.md tracks each item
docs/                       ARCHITECTURE.md, TOOL-LIST.md, baselines/
```

## Add a tool

1. Copy `Nutmeg.AD/Tools/_ToolTemplate.ps1` to `Nutmeg.AD/Tools/<Category>/<Verb>-Nm<Thing>.ps1`.
2. Fill in the `$NmTool` block and the entry function. `Area` says where it shows in the menu
   (`gpo/Baselines`, `ad/Structure`, `ready`, `report`, `kit`). List the modules it needs in
   `Services` (`AD`, `GPO`); don't load them yourself. Send every AD call to the session's DC with
   `Get-NmADParams` (GroupPolicy cmdlets: `Get-NmGPParams`).
3. Change tools call `Confirm-NmChange` before every write and support `-WhatIf`.
4. Run `.\Tests\Invoke-AllTests.ps1`, then start the toolkit. A tool with a problem in its metadata
   shows under **Tools not loaded** with the reason.

## Intake

Source material lives under `Legacy/` (see `Legacy/README.md` and `Legacy/INDEX.md`): scripts,
screenshots, and the GPO HTML reports the baselines are built from. Nothing there is loaded by the
toolkit.
