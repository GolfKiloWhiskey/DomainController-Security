# Legacy intake

Source material for the toolkit, kept as it was sent. Nothing here is loaded by the module.

- **Scripts/**: existing scripts. Add them as they are; don't clean them up first.
- **Screenshots/**: screenshots of settings, wizards or steps to turn into scripts. Name them so the
  order is clear when several belong together (`01-dns-forwarders.png`, `02-...`).
- **GPO-Reports/**: GPO HTML reports. One file per GPO, named after the GPO. A GPO backup folder
  (from `Backup-GPO`) can sit next to its report if you have one.

Before committing, take out anything client-specific: real domain names, server names, IP addresses,
passwords, keys and certificate files. Use placeholders such as `clientx.local`, `DC01`, `192.0.2.10`.
If that is too much work for a batch, say so and it will be scrubbed when the item is ported.
