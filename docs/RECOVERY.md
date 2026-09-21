# Recovery-first operation

Before `apply`, run an audit, retain its output directory, read
`restore-user0.sh`, and establish a tested rollback path. Then run:

```sh
scripts/mantis-tool.sh --serial SERIAL --baseline AUDIT_DIRECTORY verify
scripts/mantis-tool.sh --serial SERIAL verify-settings
```

Use the exact serial for the approved target. `verify` requires preserved
packages, Bluetooth, the exact Wolf identity and activity, locale continuity,
WireGuard Always-on/lockdown continuity, tun0 presence, Settings resolvers,
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
setting. Accessibility, Display & Sounds, Date & Time, and Language are
permission-protected from shell launch on this Fire OS build. Their smoke path
uses the stock long-press-Home HUD and D-pad navigation; a permission denial is
expected only for those routes, and a missing rendered hierarchy is a failure.

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

Do not reboot before pre-reboot verification and a rollback rehearsal. Locale
is never changed by this controller. If a preferred language is offered, use
only stock Settings > Language, record the original locale first, and return
through the same stock UI to roll back. Ukrainian was not offered in the
observed stock list, so `UKRAINIAN_LOCALE=UNAVAILABLE`.
