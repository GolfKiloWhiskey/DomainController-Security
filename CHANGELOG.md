# Changelog

Newest first. Version numbers are the module's (`Nutmeg.AD.psd1`).

## 0.2.1 - 11/21/2026

- **`Get-NutmegAD.ps1` puts the toolkit on a server**, or updates it. It is a standalone script,
  not part of the module: copy the one file to the server (or paste it into Windows PowerShell).
  - Asks for a GitHub token without showing it, and never saves or logs it. Use a fine-grained token
    for this repository only, with Contents: Read-only.
  - Downloads the branch you name (`main` by default) into `C:\Tools\DomainController-Security`, checks
    it really is the toolkit, keeps the copy that was there as `.previous`, and unblocks the files.
  - Shows the toolkit version and commit. `-StartBuild` goes straight into the New Forest Build.

## 0.2.0 - 11/21/2026

The New Forest Build's first two phases: a freshly installed Windows Server to the first DC of a new
forest. Built first so it can be tested on a checkpointed VM again and again.

- **Start it with `.\Start-NutmegAD.ps1 -NewForest`** on the workgroup server. It always runs in
  Windows PowerShell 5.1 (the server role modules live there) and offers to restart as administrator.
- **Pre-flight first, before any question.** It stops, changing nothing, if PowerShell isn't 5.1, it
  isn't elevated, the server is not Windows Server 2016 or later or is already a DC, it is joined to
  a domain, toolkit files are still blocked from the download, or there is no network. It warns about a
  pending restart, low disk space and a second network adapter, and notes the hypervisor.
- **Then every question, once:** domain name and NetBIOS name, functional level (2025, or 2016 if
  older DCs may join), whether more DCs are planned, computer name, time zone, the network adapter (if
  there are several), the static IP (offers `.50` in the current subnet), prefix, gateway, DNS until
  promotion, and the database folders (C:\Windows by default). It refuses a domain that already
  answers on the network, or an address something already answers on.
- **One approval:** the whole plan is shown and approved by typing the domain's short name. Nothing
  else is asked until the DSRM password.
- **Phase 0:** time zone, computer name, a sign-in task that reopens the build after each restart,
  then the static IP (last, because it drops an RDP session to the old address; it says the new one).
  Restarts if the name changed; otherwise it carries straight on.
- **Phase 1:** installs AD DS, DNS, Group Policy Management and the AD module, asks for the DSRM
  password twice (never saved or logged), runs Microsoft's own pre-checks, creates the forest and
  restarts.
- **After the restart:** sign in as `<NETBIOS>\Administrator`; the build reopens, checks the new DC
  answers for the domain, removes the sign-in task and saves the answers to `C:\Temp` as a record.
- **It picks up where it stopped.** Every step is recorded in `C:\Temp\NutmegAD\NewForest\State.json`.
  After a failure, fix the cause and run it again: finished steps are skipped.
- Phases 2 to 5 (DNS, time, OUs, GPOs, report) come next.
- Not run on Windows yet: tested against stand-ins for the server. `docs/NEW-FOREST-TESTING.md` is the
  checklist for the first runs on the VM.

## 0.1.0 - 11/20/2026

The first working version: the toolkit opens, finds the domain and runs its first tool.

- **Start it with `.\Start-NutmegAD.ps1`.** It works in Windows PowerShell 5.1 and PowerShell 7.
  - Not running as administrator: it offers to start again elevated.
  - In 5.1 it offers to start again in PowerShell 7. If 7 isn't installed, it offers to install the
    current LTS release from Microsoft. The download is only run if it is signed by Microsoft, and it
    is installed with Microsoft Update on, so it gets patched with Windows.
- **The main menu** has the areas from the tool list (Group Policy, Active Directory, Hardening
  readiness, Reports, Toolkit), Search, Domain and DC, Run history and Settings. Areas show up as
  their tools are added.
- **Nothing loads at start.** The first tool that needs the ActiveDirectory or GroupPolicy module
  loads it and reads the domain from this DC. Domain and DC shows the domain, its levels and the PDC,
  and can point the toolkit at another DC.
- **Changes always ask first.** A change to the whole domain, or to more than 25 objects, needs the
  domain's short name typed (for clientx.local: `clientx`).
- **Session and Prerequisite Check** (`session-info`, Toolkit > Diagnostics): PowerShell version,
  elevation, whether this is a DC, the AD and GroupPolicy modules, the domain and forest, whether
  you are in Domain, Schema and Enterprise Admins, and where logs and exports go.
- Logs, run history and exports go under `C:\Temp` as in the M365 toolkit (`C:\Temp\NutmegAD` for
  logs and history). Settings are per Windows user in `%APPDATA%\NutmegAD\Settings.json`.
- Not tested on a real DC yet: everything was tested against stand-ins for AD.
