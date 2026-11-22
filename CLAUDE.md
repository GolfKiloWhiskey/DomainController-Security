# CLAUDE.md: working on Nutmeg.AD

Read this before changing anything. Nutmeg.AD is Cliff Waite's PowerShell toolkit (Nutmeg Technologies,
an MSP) for Active Directory domain controller onboarding: what happens after a DC is built, such as OU
layout, GPO baselines, hardening, reports and health checks.

**Building a DC is out of scope, with one planned exception.** No tool installs AD DS, runs
`Install-ADDSForest` / `Install-ADDSDomainController` or demotes a DC, except the planned **New Forest
Build** (`docs/TOOL-LIST.md`): one guarded run for the first DC of a brand-new forest, which refuses to
run on a domain-joined server or when a domain of that name already answers. Further DCs, and existing
domains, are always worked on with the individual tools.

**Hardening is the GPO baselines.** DC and domain hardening is defined by Cliff's GPO reports in
`Legacy/GPO-Reports/`. Tools build, link and check those GPOs; don't add separate hardening scripts that
set the same things outside Group Policy. A setting that can't be done in a GPO is the exception, and is
agreed with Cliff first.

**A baseline is a GPO's settings, nothing else.** The reports in `Legacy/GPO-Reports/` come from one
client build; their links, delegation, security filtering, WMI filters, owners and IDs belong to that
client and are not part of the baseline. Values that depend on the environment (server names, paths,
IP ranges, SSID, CA, disclaimer text, renamed account names, the Duo installer and settings) are
parameters, asked for at build time with sensible defaults. Links, delegation, filtering and WMI
filters are chosen by the technician on each run, GPO by GPO: no GPO is set up the same way, so there is
no "build everything" button.

**It runs on a DC**, elevated, as a domain admin; other DCs are reached from there. **OU standard:** one
organization OU directly under the domain root (`OU=<CompanyName>,DC=clientx,DC=local`), with all
structured OUs (Devices, Security Groups, Service Accounts, Users and so on) below it. The one exception:
`Z-Disabled Users` and `Z-Disabled Computers` sit directly under the domain root, outside the Entra Connect
sync scope. **Firewall GPOs always merge local rules** (Cliff's standard): never set "Apply local firewall
rules" to No, least of all on a GPO that reaches DCs.

## Baseline: M365-Tools

The Nutmeg M365 Toolkit (`GolfKiloWhiskey/M365-Tools`) is the reference for how this toolkit is set up:
the module layout, the core (menus, logging, `Confirm-NmChange`, exports, settings, tool registry), the
console menu and the WPF window, the tool template, the tests against fakes and the delivery rules. It is
a pattern to follow, **not a shared dependency**: copy and adapt what is needed into this repo; never
import or reference M365-Tools code at run time. Its `CLAUDE.md` lessons apply here where they are about
PowerShell, the window or tests.

## Status

Building, in the order in `docs/TOOL-LIST.md` (agreed with Cliff, Nov 2026). Done: step 1, the core and
launcher (0.1.0) and `session-info`; the New Forest Build's phases 0 and 1 (0.2.0, moved ahead by Cliff
to test on a checkpointed Server 2025 VM, passed QA); the WPF window (0.3.0, `Core/Gui.ps1`,
now the launcher's default, `-Console` for the console); the build in the window (0.4.0, opened by
`Get-NutmegAD.ps1`, which also installs PowerShell 7). The launcher uses PowerShell 7 whenever it is
installed (0.6.0). The build runs in Windows PowerShell 5.1 only. Since then: the build runs its long
steps in the background behind a live step list (`Core/Steps.ps1`, 0.7.4) and ends with an HTML and
PDF report (`Core/Report.ps1`, headless Edge) after the DC health checks and dcdiag
(`Core/DcHealth.ps1`, 0.7.7); `dc-report` (Reports) writes the same report for this DC, another or
every DC (0.7.8, waiting for Cliff's console QA). **DNS standard** (Cliff, 0.7.9): 1.1.1.1 is always
the last DNS server on a DC's adapter (setting `BuildLastDns`), so the RMM agent stays reachable;
the build ends with its own IP, 127.0.0.1, 1.1.1.1, and the health check warns when it is missing.
Step 2 is built (0.7.11, console QA pending): the baseline file format (`docs/baselines/FORMAT.md`,
`Nutmeg.AD/Baselines/`), `gpo-build` and `gpo-compare`, with the first nine baselines.
Read `docs/ARCHITECTURE.md` next for how the pieces fit together.
Source material is in `Legacy/` and tracked in `Legacy/INDEX.md`.

## How work is delivered

- **Console first, then the window** (Cliff, Nov 2026). Every step is built and passes Cliff's QA in
  the console before it goes into the WPF window (ported from M365-Tools in 0.3.0). A step may go straight into the
  window only when Cliff and Claude both agree to it for that step.

- **Check GitHub before any new work** (Cliff, Nov 2026): list the open PRs and fetch `main`. One PR
  at a time, always started from the newest `main`. Never build on a PR that is not merged, and never
  ask Cliff to merge one: he merges before asking for more. If one is still open, say it is pending.
- **Work on the session's branch and open the PR against `main`.** One PR per piece of work; Cliff
  merges, never merge yourself.
- **Every PR also updates:** the version in `Nutmeg.AD.psd1` (`ModuleVersion`) and in `Nutmeg.AD.psm1`
  (`$script:ModuleVersion`, the header's `Version:` and a line at the top of `.VERSIONING`);
  `CHANGELOG.md` (newest first, plain words, for Cliff); `README.md` when something user-visible
  changes; `docs/TOOL-LIST.md` when a step starts or finishes; `Legacy/INDEX.md` when a legacy item is
  ported; a tool's own `Version` and `.VERSIONING` when it changes.
- **Version numbers move slowly** (Cliff, Nov 2026). Every PR adds 1 to the last number only:
  0.7.1, 0.7.2, ... (0.7.15 is fine; it never rolls over into the middle number). The middle number
  moves only at a milestone Cliff names. `1.0.0-beta` is the whole package built and ready for
  release testing; `1.0.0` is the release. Tools follow the same rule for their own `Version`
  (0.7 -> 0.7.1 -> 0.7.2). The module manifest's `ModuleVersion` takes only the numbers, so the beta
  is also marked with `Prerelease = 'beta'` in `PrivateData.PSData` then.

## PowerShell version

- **Target PowerShell 7 (7.6 LTS)** for the toolkit itself. Microsoft's module list: `ActiveDirectory`
  is natively compatible; `GroupPolicy` is untested with the compatibility layer. Load `GroupPolicy`
  with `Import-Module -UseWindowsPowerShell` (as M365-Tools does for SharePoint), and read properties of
  what comes back, don't call methods: objects arrive deserialized.
- **The launcher must still start in Windows PowerShell 5.1**, because a newly built DC has only 5.1
  until PS7 is installed. In 5.1 it offers to install PowerShell 7 (MSI, with Microsoft Update enabled) and relaunches in
  `pwsh`. Keep the launcher and anything it calls 5.1-safe (no `?:`, `??`, `?.`).
- **PowerShell 7 on a DC must be logged and patched like Windows PowerShell.** PS7 has its own policy
  keys (`HKLM\Software\Policies\Microsoft\PowerShellCore`) and its own ADMX ("PowerShell Core"); a
  baseline that only sets the Windows PowerShell policies leaves `pwsh` unlogged. The GPO baseline must
  set script block logging, module logging, transcription and execution policy for PowerShell Core too
  (or tick "Use Windows PowerShell Policy setting"), and the health check must verify it. PS7 is only
  patched by Microsoft Update if the MSI was installed with that option.

## Writing a tool

- **The core loads modules, reads the domain, exports, logs and draws the results. A tool declares
  what it needs and returns objects.** List `Services` (`AD`, `GPO`) in `$NmTool`; never
  `Import-Module` ActiveDirectory or GroupPolicy yourself. `session-info` is the one exception: it
  loads AD itself so it can report a missing module.
- **One DC per run.** Splat `Get-NmADParams` onto every AD cmdlet and `Get-NmGPParams` onto every
  GroupPolicy cmdlet, so a run reads and writes one copy of the directory.
- **GroupPolicy objects come through Windows PowerShell in PowerShell 7.** Read properties; never call
  methods on them.
- **Questions only through the core helpers** (`Show-NmMenu`, `Read-NmMultiChoice`, `Read-NmInput`,
  `Read-NmYesNo`, `Wait-NmKey`). Never `Read-Host`: a core test fails on it.
- **Change tools** take `[switch]$WhatIf`, call `Confirm-NmChange -Action ... -Targets ... -WhatIf:$WhatIf`
  before every write (`-DomainWide` for a change to the whole domain, such as a GPO linked at the root;
  `-RequireTyped` for anything hard to undo), record each change with `Write-NmRunHistory`, and return
  a row per target with a `Result` column ("Created", "Already there", "Failed: reason",
  "WhatIf: not changed", "Cancelled").
- **Placement:** `Area = '<area>/<Section>'`: `gpo`, `ad`, `ready`, `report`, `kit` (`$script:NmAdminCenters`
  in `Core/ToolRegistry.ps1`). A new section name is allowed; an unknown area fails to load.
- **Progress** with `Write-Progress -Status "[i/n] item"` and `-Completed`; **tables** with `Format-Table`
  or `Format-List` piped to `Out-Host`. Don't cut text short.

## Hard rules (carried over from M365-Tools)

- **No secrets or client data in the repo**: no passwords, keys, certificates, real
  domain, server or client names, or real IP addresses. Use `clientx.local`, `DC01`, `192.0.2.x`.
- **Code files are ASCII only** (`.ps1`, `.psm1`, `.psd1`).
- **Change tools** confirm every write with `Confirm-NmChange`, support `-WhatIf`, record run history and
  return a `Result` per target. Forest- or domain-wide changes need the domain name typed.
- **Cliff's script standard** for every tool file: header with `.NOTES` (Author, Date, Email, Version),
  `.SYNOPSIS`, `.DESCRIPTION` as bullets, `.EXAMPLE`, `.VERSIONING`; logging through `Write-NmLog`;
  menu-driven; exports under `C:\Temp`.
- **Everything in the module runs in Windows PowerShell 5.1 too** (the launcher starts there): no `?:`,
  `??`, `?.`, `ForEach-Object -Parallel` or `-AsHashtable`, and flatten `ConvertFrom-Json` results.
- **Ask before building anything big or ambiguous.** Small fixes and clear requests: just do them.

## Lessons from M365-Tools that apply here

- `continue` inside a `switch` only leaves the switch, not the loop around it.
- `-match` ignores case; use `-cmatch` when case matters.
- An `if` whose result is one array element hands back the element: wrap it, `$x = @(if (...) { ... })`.
- `return , @(...)` nests the array when the caller writes `@(f)`. Return plain arrays.
- `$sender`, `$args`, `$input`, `$matches`, `$this` and `$event` are automatic variables; don't use them as parameter names.
- `"$word:"` is read as a scope-qualified variable; write `"${word}:"`.
- PowerShell 7's `-Encoding UTF8` writes no BOM; CSV exports use `Get-NmCsvArgs`.
- A dot-sourced tool silently replaces a core function of the same name; check with `Get-Command` first.
- Test fakes must refuse what the real cmdlet refuses, or they hide real bugs.
- Tests never touch the technician's settings: each test file sets `$script:NmSettingsTestFile`.

## Tests and checks

- **Run everything:** `pwsh -File ./Tests/Invoke-AllTests.ps1` (fakes only: no domain, no AD module).
- **Every tool change gets tests**, and every bug fix a test that fails without the fix.
- **PSScriptAnalyzer** (Warning and Error) on what changed, with M365-Tools' excluded rules.
- **ASCII** is checked by the core tests.
- Nothing here has run on a real DC unless the PR says so: say plainly what was not tested on Windows.
