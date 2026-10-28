# Recovery-first operation

For deployment, `--serial` must be an authorized physical USB ADB connection
shown with `usb:` in `adb devices -l`; `--network-serial` must be the same
stick's separate `IP:5555` connection. If preflight reports a missing core
package, including `com.amazon.dp.logger`, restore its original enabled state
before deployment. The script will not enable it for you.

If debloat stops and says rollback is incomplete, save the entire checksummed
backup directory. Reconnect both ADB transports and run the backup's
`restore-user0.sh` if you want to restore the changes recorded in that run.
Restore keeps ledger entries until package state and all guards can be checked.
If the old backup is gone, reconnect both ADB transports and rerun the
deployment script. It creates a new backup from the current state and skips
already-disabled packages. It cannot reconstruct the lost original baseline
or undo earlier root-only changes. If the previous run attempted root and
failed, reboot before rerunning to give the exploit a fresh boot.

```sh
SERIAL=USB_SERIAL NETWORK_SERIAL=DEVICE_IP:5555 \
  "$HOME/firetv-mantis-backups/deployment-TIMESTAMP/debloat-backup/restore-user0.sh"
```

Before `apply`, run an audit, retain its output directory, read
`restore-user0.sh`, and establish a tested rollback path. Then run:

```sh
scripts/mantis-tool.sh --serial SERIAL --baseline AUDIT_DIRECTORY verify
scripts/mantis-tool.sh --serial SERIAL verify-settings
```

Use the exact serial for the approved target. `verify` requires core packages
and user apps present in the backup, Bluetooth, the exact Wolf identity and
activity, locale continuity,
WireGuard Always-on/lockdown and tun0 continuity, Settings resolvers,
ADB Debugging, running adbd, USB ADB configuration, configured TCP 5555, and a
reachable TCP ADB transport. It reports TCP 8009 separately from
`NETWORK_REMOTE_OBSERVED=UNVERIFIED`; a listener alone is not proof of
end-to-end remote input.

When the primary serial is USB, supply `--network-serial SERIAL:5555` so the
network transport is independently probed. The audit baseline records the
persistent TCP-port property exactly; it may be empty, while the running TCP
service still must be port 5555.

`settings-route-resolvers.raw.txt` preserves each resolver output line with its
action prefix. `settings-route-resolvers.txt` is the strict parsed baseline: it
contains exactly one stock component for each of the ten required actions.
Diagnostic metadata is accepted only in the known Fire OS grammar. Verify,
apply, rollback, and fresh restore reject missing, duplicated, malformed,
foreign, or changed route components.

`verify-settings` resolves every essential route, including Developer Options,
then checks a focused component and non-empty hierarchy without changing a
setting. It first opens the exact `com.amazon.tv.settings.v2/.hud.HudActivity`,
requires the `hud_settings_button` node to be enabled, focusable, and clickable,
and confirms that node is focused before Select enters the stock Settings task.
Key 176 is tried first, but its command status is not trusted: if bounded exact
HUD-focus checks miss, long-press Home is tried and must prove that same focus.
Transient HUD focus loss is detected before Select and retried twice; a
persistent failure stops verification. A
resumed subpage is valid for this user-facing HUD proof only when it is an exact
component already present in the protected Settings route table; unchanged HUD
focus and unknown `settings.v2` activities fail closed. Accessibility,
Display & Sounds, Date & Time, Language, and the main Settings action are
unsafe to launch by generic shell action on this Fire OS build: a compliance
handler can loop while no window is focused. Each such route instead launches
`com.amazon.tv.launcher/.ui.MainSettingsActivity` with Android's exact
`0x04000000` `CLEAR_TOP` flag, verifies exact root focus, then follows
deterministic D-pad navigation. The verifier waits until the root grid's
Network tile is focused, then checks each intended tile before Select; this
prevents a retained grid focus from opening the wrong page. The checked
resolver remains the route-identity proof. A missing hierarchy is a failure.

Audit and plan must both report:

```text
PACKAGE_OPERATION=pm disable-user --user 0
PACKAGE_RESTORE=pm enable --user 0
```

If either line is `unsupported`, stop. The controller requires `pm help` to
prove both syntaxes. `apply` disables packages for user 0; it does not uninstall
their APKs or modify the system image. The checksummed backup records only
candidates whose transition to the disabled inventory was verified. Candidates
that were already disabled are skipped and are not later enabled by restore.
Do not manually disable `com.amazon.ftvads.deeplinking` or
`com.amazon.tv.csapp`: this exact NS6711 build marks both protected, and the
controller requires them to remain enabled through the core-preservation guard.
Appstore (`com.amazon.venezia`) also rejects the shell-stage operation, so it
and `com.imdb.livingroom.firetv` are hidden by the guarded root stage and
recorded in `root-actions.journal`.

If the screen is black or the launcher path is unhealthy, stop package actions.
Keep the stock remote path, return to stock Home/Settings, and restore the
recorded successful-disable ledger in reverse order:

```sh
scripts/mantis-tool.sh --serial SERIAL restore AUDIT_DIRECTORY
```

The generated `restore-user0.sh` is a resumable entry point tied to its audit
directory. It invokes the reviewed controller at the path embedded when the
audit was created; if that checkout moved, set `MANTIS_TOOL` to the reviewed
`mantis-tool.sh`. It forwards `ADB`, `SERIAL`, and optional `NETWORK_SERIAL` to
the same restore implementation rather than maintaining a weaker second copy.

Restore verifies the directory's checksums, package-operation mode, exact
target, and manifest ownership. It reconciles interrupted disables, then uses
the checksummed `restore-journal.txt` to reconcile only journal-backed ledger
entries that are already observed enabled. An enable that changed state despite
a nonzero command result is accepted only after both package inventories prove
the transition. After every successful or reconciled enable, the controller
runs the preserved-app, Bluetooth, Whisper/Home/Settings, VPN, and USB/network
ADB guards before removing that package from the checksummed ledger. A failed
guard retains the ledger entry and prevents `RESTORE=PASS`.

The protected stock Home activity and six root-only hidden packages (three
OTA packages, Appstore, visible IMDb, and Home-starter) require a fresh temporary root
session to restore. Stage `scripts/device-root-restore.sh` and the original
`root-actions.journal` plus `root-actions.journal.md5` together as the mandatory
`--exec` operation for the exact-build exploit. The deployment extracts this
journal from `[journal]` lines in the retained `root.log` and checksums it on
the controller host; keep all three files together and do not edit them. The
restore script verifies the journal with the build's observed
`/system/bin/md5sum`, then enables or unhides only entries that the journal
records as changed by that deployment. Verify that it reports
`ROOT_RESTORE=PASS` before rebooting. Restore the ordinary user-0 package
ledger separately with `mantis-tool.sh restore`; do not treat a root restore as
a substitute for that checksummed inverse.
Older checksummed backups that recorded a screensaver disable are still
restorable with the current `mantis-tool.sh restore` command.

Do not reboot before pre-reboot verification and a rollback rehearsal. Locale
is never changed by this controller. If a locale is changed separately, record
the original value and verify the active Android configuration after reboot.
