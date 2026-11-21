# Testing the New Forest Build on a VM

For Cliff's checkpointed Windows Server 2025 VM (taken right after the OS install). Roll back to the
checkpoint before each run: the build's state file lives on the VM, so a rollback starts it fresh.

## Before the first run

1. Copy `Get-NutmegAD.ps1` onto the VM and run it in Windows PowerShell as administrator. While the
   build is still in review, name its branch:
   ```powershell
   .\Get-NutmegAD.ps1 -Branch claude/zen-franklin-4swcvy
   ```
   It asks for a GitHub token (hidden, never saved), puts the toolkit in
   `C:\Tools\DomainController-Security`, unblocks the files, installs PowerShell 7 if it is missing
   (no question; a minute or two), and opens the New Forest Build **in the window** (since 0.4.0).
   `-Console` runs the build in the console as before. After a fix, run it again to update.
2. (Done by `Get-NutmegAD.ps1`.) Copied any other way, unblock the files once:
   ```powershell
   Get-ChildItem C:\Tools\DomainController-Security -Recurse | Unblock-File
   ```
   Pre-flight stops on blocked files, because the sign-in task could not run them after a restart.
3. Give the local Administrator a strong password. It becomes the domain's Administrator password, and
   Microsoft's pre-checks refuse a weak one.
4. Take the checkpoint here if you want to skip steps 1 to 3 next time.

## A run

1. `Get-NutmegAD.ps1` opens the build in the window. To start it yourself, sign in as the local
   Administrator, open **Windows PowerShell** as administrator and run:
   ```powershell
   cd C:\Tools\DomainController-Security
   .\Start-NutmegAD.ps1 -NewForest     # the window (add -Console for the console)
   ```
   In the window (0.5.0) the questions come one at a time, in the console's order, as clean
   dialogs: the server check as a table in the first one, the suggested answer already in the box,
   a red line when an answer is refused. The plan is an approval dialog (type the short name,
   then Approve), and the DSRM password a password box. The role install, the pre-checks and the
   forest run in the background: the window keeps responding, with the elapsed time at the bottom.
   **Start or continue the build** starts the questions again.
2. **Pre-flight table:** everything OK, or Warning only. A Not ready row stops the run and changes nothing.
3. **Questions:** domain, NetBIOS, level, more DCs, computer name, time zone, adapter, IP (`.50` offered),
   prefix, gateway, DNS until promotion, folders.
4. **Plan:** read it, then type the domain's short name (`clientx` for clientx.local).
5. **Phase 0:** time zone, name, sign-in task, static IP. If you are on RDP to the DHCP address, it
   drops here: reconnect to the new IP. With a new name it restarts after 60 seconds.
6. **After the restart:** sign in as the local Administrator. The build reopens (the window, if it
   was started there, with a Windows PowerShell console behind it): answer **Yes** to continue.
7. **Phase 1:** roles install (a few minutes), then the DSRM password twice, Microsoft's pre-checks,
   the forest (several minutes), and a restart after 60 seconds.
8. **After the second restart:** sign in as `<NETBIOS>\Administrator` (same password as the local one
   was). The build reopens: **Yes**. It checks the DC, removes the sign-in task and saves a record.

## What to check, and send back

- The pre-flight table and the results table of each phase (a screenshot is fine).
- `Get-NetIPConfiguration`: the static IP, gateway and DNS (after promotion DNS should be `127.0.0.1`,
  set by Windows itself).
- `Get-ADDomain` and `Get-ADForest`: names and levels as answered.
- `Get-ScheduledTask -TaskName 'Nutmeg AD Toolkit - New Forest Build'`: gone at the end (while the
  build runs in the console, its action ends in `-NewForest -Console`; in the window, in `-NewForest`).
- `pwsh -v`: PowerShell 7 installed by `Get-NutmegAD.ps1`, and the log says `Approved with the plan
  'Get-NutmegAD.ps1: PowerShell 7 is part of every toolkit server'`.
- `C:\Temp\NutmegAD\NewForest\State.json`: every step Done, and no password in it.
- `C:\Temp\NutmegAD\Logs\NutmegAD_*.txt`: since 0.2.7 the whole build, from `Get-NutmegAD.ps1` to the
  finished DC, is one log (the newest file started before the build). Each restart shows as a
  `---- Session continued ----` line, and each step as `Build step done: ...`.

## Things worth trying on purpose

- Run it in PowerShell 7 (`pwsh .\Start-NutmegAD.ps1 -NewForest`): it should hand over to Windows PowerShell.
- Answer a single-label domain (`clientx`) or a 16-character NetBIOS name: asked again.
- Type the wrong word at the plan: nothing changes, no state file.
- Close the window during phase 1 before the DSRM password, then run step 1 again: it continues.
- Cancel the DSRM password dialog: the build stops with nothing made; run it again and it continues.
- `.\Get-NutmegAD.ps1 -Console`: the same build in the console.
- Cancel at the NetBIOS question, then **Start or continue the build**: it offers the saved answers
  (Yes skips the domain name; No asks everything again). Change the domain name when carrying on:
  NetBIOS is asked again.
- Type an address that answers (the gateway) at the static IP question: refused in red, asked again.
- Pending restart: the check shows a Warning; with the name kept, phase 0 still restarts. If Windows
  wants another restart before AD DS (an update), the build stops with Restart now / Restart in
  30 minutes; try the 30-minute choice and watch for the 5-minute reminders.
- Keep the computer name: no restart after phase 0; phase 1 follows straight away.
