# CLAUDE.md: working on Nutmeg.AD

Read this before changing anything. Nutmeg.AD is Cliff Waite's PowerShell toolkit (Nutmeg Technologies,
an MSP) for Active Directory domain controller onboarding: what happens after a DC is built, such as OU
layout, GPO baselines, hardening, reports and health checks.

**Out of scope: building a DC.** Installing AD DS, creating a forest or domain and promoting DCs are
always done by hand. No tool installs AD DS, runs `Install-ADDSForest` / `Install-ADDSDomainController`
or demotes a DC.

## Baseline: M365-Tools

The Nutmeg M365 Toolkit (`GolfKiloWhiskey/M365-Tools`) is the reference for how this toolkit is set up:
the module layout, the core (menus, logging, `Confirm-NmChange`, exports, settings, tool registry), the
console menu and the WPF window, the tool template, the tests against fakes and the delivery rules. It is
a pattern to follow, **not a shared dependency**: copy and adapt what is needed into this repo; never
import or reference M365-Tools code at run time. Its `CLAUDE.md` lessons apply here where they are about
PowerShell, the window or tests.

## Status

Intake. Source material is in `Legacy/` and tracked in `Legacy/INDEX.md`. The tool list is agreed with
Cliff before any module code is written.

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

## Hard rules (carried over from M365-Tools)

- **No secrets or client data in the repo**: no passwords, keys, certificates, real
  domain, server or client names, or real IP addresses. Use `clientx.local`, `DC01`, `192.0.2.x`.
- **Code files are ASCII only** (`.ps1`, `.psm1`, `.psd1`).
- **Change tools** confirm every write with `Confirm-NmChange`, support `-WhatIf`, record run history and
  return a `Result` per target. Forest- or domain-wide changes need the domain name typed.
- **Ask questions only through the core helpers**; never `Read-Host`.
- **Cliff's script standard** for every tool file: header with `.NOTES` (Author, Date, Email, Version),
  `.SYNOPSIS`, `.DESCRIPTION` as bullets, `.EXAMPLE`, `.VERSIONING`; logging through `Write-NmLog`;
  menu-driven; exports under `C:\Temp`.
- **Ask before building anything big or ambiguous.** Small fixes and clear requests: just do them.
