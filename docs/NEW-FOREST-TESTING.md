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
   `C:\Tools\DomainController-Security` and unblocks the files. After a fix, run it again to update.
2. (Done by `Get-NutmegAD.ps1`.) Copied any other way, unblock the files once:
   ```powershell
   Get-ChildItem C:\Tools\DomainController-Security -Recurse | Unblock-File
   ```
   Pre-flight stops on blocked files, because the sign-in task could not run them after a restart.
3. Give the local Administrator a strong password. It becomes the domain's Administrator password, and
   Microsoft's pre-checks refuse a weak one.
4. Take the checkpoint here if you want to skip steps 1 to 3 next time.

## A run

1. Sign in as the local Administrator, open **Windows PowerShell** (not 7) as administrator and run:
   ```powershell
   cd C:\Tools\DomainController-Security
   .\Start-NutmegAD.ps1 -NewForest
   ```
2. **Pre-flight table:** everything OK, or Warning only. A Not ready row stops the run and changes nothing.
3. **Questions:** domain, NetBIOS, level, more DCs, computer name, time zone, adapter, IP (`.50` offered),
   prefix, gateway, DNS until promotion, folders.
4. **Plan:** read it, then type the domain's short name (`clientx` for clientx.local).
5. **Phase 0:** time zone, name, sign-in task, static IP. If you are on RDP to the DHCP address, it
   drops here: reconnect to the new IP. With a new name it restarts after 60 seconds.
6. **After the restart:** sign in as the local Administrator. Windows PowerShell opens on the build:
   answer **Y** to continue.
7. **Phase 1:** roles install (a few minutes), then the DSRM password twice, Microsoft's pre-checks,
   the forest (several minutes), and a restart after 60 seconds.
8. **After the second restart:** sign in as `<NETBIOS>\Administrator` (same password as the local one
   was). The build reopens: **Y**. It checks the DC, removes the sign-in task and saves a record.

## What to check, and send back

- The pre-flight table and the results table of each phase (a screenshot is fine).
- `Get-NetIPConfiguration`: the static IP, gateway and DNS (after promotion DNS should be `127.0.0.1`,
  set by Windows itself).
- `Get-ADDomain` and `Get-ADForest`: names and levels as answered.
- `Get-ScheduledTask -TaskName 'Nutmeg AD Toolkit - New Forest Build'`: gone at the end.
- `C:\Temp\NutmegAD\NewForest\State.json`: every step Done, and no password in it.
- `C:\Temp\NutmegAD\Logs\NutmegAD_*.txt`: the session logs, for anything that went wrong.

## Things worth trying on purpose

- Run it in PowerShell 7 (`pwsh .\Start-NutmegAD.ps1 -NewForest`): it should hand over to Windows PowerShell.
- Answer a single-label domain (`clientx`) or a 16-character NetBIOS name: asked again.
- Type the wrong word at the plan: nothing changes, no state file.
- Close the window during phase 1 before the DSRM password, then run step 1 again: it continues.
- Keep the computer name: no restart after phase 0; phase 1 follows straight away.
