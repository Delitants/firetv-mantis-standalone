# Fire TV Mantis Standalone

An intentionally narrow, recovery-first controller for the exact Amazon
`mantis/AFTMM` Fire OS target documented in `docs/MODEL-SAFETY.md`. It audits,
plans reversible per-user package disables, verifies a pinned Wolf Launcher,
and refuses operations outside that boundary.

The repository includes the exact-build temporary-root port as a patch against
its unlicensed upstream base, plus a guarded end-to-end deployment script. It
does not include a compiled exploit, APK, firmware/kernel image, device backup,
connection data, or credential. See `exploit/README.md` for provenance and
`docs/DEPLOYED-STATE.md` for the verified result and recovery boundary.

The complete workflow is `scripts/deploy-mantis.sh`. It requires explicit USB
and network ADB serials, a locally built root binary, an output directory, and
`--yes`. It verifies the exact model/build over both transports before any
mutation, installs pinned Wolf Launcher and Aurora Store APKs after signature
checks, performs the 30-package reversible user-0 debloat, runs the exec-only
root stage for five exact packages plus the two stock Home components, reboots,
repeats full QA, and captures the final Wolf Home screenshot. Run it only after
reading `docs/RECOVERY.md`.

This build does not provide device-side SHA-256. The deployer therefore pulls
each staged root input back over the selected ADB transport and compares its
SHA-256 on the host. APK, profile, and exploit artifact SHA-256 gates remain
unchanged. The root action journal uses the observed device `md5sum` solely as
a tamper/corruption check for its restorative state file.

Start with an audit, read the generated restore script, run `--baseline AUDIT_DIRECTORY verify` (and `--network-serial SERIAL:5555` before it when the primary serial is USB), and use
`verify-settings` before any package action. The latter only opens stock
Settings routes and backs out; it never writes a setting. See
`docs/RECOVERY.md` before using `apply` or `restore`.

The Settings smoke test proves the build's `settings.v2` HUD and its enabled,
focusable, clickable Settings tile once. Because tile selection may resume a
known stock subpage, its post-Select focus must match the exact Settings route
table or stock root. Every permission-protected route is then navigated from a
fresh, explicit `CLEAR_TOP` launch of the exact stock Settings root so an old
Settings task cannot silently resume its last subpage.
HUD entry observes exact focus after key 176 and falls back to long-press Home
when that key reports success without opening the HUD.
Fire OS may return success for a protected action without leaving Home; that
result is not trusted and still must pass the explicit root and route checks.

Fire OS may print a diagnostic metadata line before a resolved component.
Audit preserves those raw Settings resolver lines separately and stores a
strictly parsed, checksummed ten-route component map. Package guards and fresh
restore load that map and require every route to remain exactly baseline-bound.

The project is English and locale-neutral. Locale changes are outside this
controller. On the recorded deployment, the Android framework locale was set
separately to `uk-UA`; Amazon Settings remains partly English because its APKs
do not contain Ukrainian resources.

The package operation is `pm disable-user --user 0`; recovery is
`pm enable --user 0`. Apps remain installed in the system image. The
controller will not apply unless `pm help` proves both exact command forms,
and it verifies every transition with the enabled (`-e`) and disabled (`-d`)
package inventories. Restore attempts and verified results are durably journaled
before the successful-disable ledger is changed, so an interrupted inverse can
be reconciled without blindly repeating `pm enable`.

On the exact NS6711 build, `com.amazon.ftvads.deeplinking`,
`com.amazon.tv.csapp`, and `com.amazon.venezia` reject the unprivileged
`disable-user` operation. The first two remain mandatory core-preserve entries.
Amazon Appstore (`com.amazon.venezia`) and the visible IMDb application
(`com.imdb.livingroom.firetv`) are instead exact, restorative root-stage
disables declared in `disable-root-packages.txt`. The separate legacy IMDb
package `com.amazon.imdb.tv.android.app` remains in the ordinary 30-package
user-0 manifest.

Every ADB client process receives `/dev/null` as stdin. This keeps the external
client from consuming controller-owned route, manifest, or recovery-ledger
loops; none of this controller's ADB commands accept an input payload.
