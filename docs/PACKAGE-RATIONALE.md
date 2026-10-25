# Package rationale

The candidate manifest is deliberately small and is validated against the
preservation manifests before any action. Its historical filename is
`remove-user0.txt`, but the operation is a per-user disable: no APK or system
image content is erased. Packages not explicitly listed are not candidates for
disablement.

The preservation lists cover stock Settings and its dependencies, Home,
Bluetooth/input, networking, DIAL/SSDP, Whisper services, package installation,
and recovery support. Protected user applications that are enabled in the
pre-change backup must remain enabled; absent apps are not installed or
required. Wolf and Aurora are installed by the deployment before that backup.
The exact NS6711 build also reports `com.amazon.ftvads.deeplinking`,
`com.amazon.tv.csapp`, and `com.amazon.venezia` as protected packages when
`pm disable-user --user 0` is attempted. The first two are mandatory core
preserve entries. Appstore (`com.amazon.venezia`) is deliberately excluded from
that preserve list and hidden for user 0 only by the exact-build, exec-only root stage.
The visible IMDb package (`com.imdb.livingroom.firetv`) follows the same
root-only path, while the separate legacy `com.amazon.imdb.tv.android.app`
package remains an ordinary user-0 candidate. The root-only package list is
closed and exact; its journal records only verified changes for restoration.
Root-only hidden packages retain their system APKs, are verified through
`dumpsys package` (`User 0: installed=true hidden=true`), and are restored with
`pm unhide --user 0`. A normal `pm disable` on these packages was observed to
revert at reboot on this build, so a post-reboot disabled-list check is not
evidence of durable removal.
The root stage also hides `com.amazon.firehomestarter` before disabling only
`com.amazon.tv.launcher/.ui.HomeActivity_vNext`. This leaves the Amazon
launcher package and its Settings activities enabled while Wolf resolves as
Home.
System Status Monitor (`com.amazon.ssm`) is also an ordinary, reversible
user-0 candidate. `com.amazon.vizzini.ftvcds` remains in core preservation for
voice dependencies; hiding its "What Should I Watch" Wolf tile does not disable
or remove that package.

The enabled package inventory (`pm list packages -e`) is the operative set.
Each candidate must begin enabled, then be absent from that inventory and
present in `pm list packages -d` after `pm disable-user --user 0`. A candidate
already present only in the disabled inventory is skipped and never recorded
for restore. A candidate in neither inventory, or in both, is a hard failure.
Only verified state transitions enter the checksummed
`disabled-successfully.txt` ledger; restore runs `pm enable --user 0` over that
ledger in reverse order and verifies the inverse transition. Before each
inverse, it writes and checksums an `attempt` in `restore-journal.txt`; a
verified result is also checksummed before the ledger entry is removed. On a
later run, only a still-recorded manifest package with that durable attempt can
be reconciled from an already-enabled state. Every successful or reconciled
enable must pass the preserved-app, Bluetooth, Whisper/Home/Settings, VPN, and
USB/network ADB guards before its ledger entry is pruned.

Wolf Launcher is pinned to version code `11900120` and version name
`0.1.9-Wolf`, package `com.wolf.firelauncher`, and its launcher activity. An
installed `0.1.7-FireTV` does not satisfy the verification gate. Artifact
provenance is limited to the recorded archive URL, fixed SHA-256, and signer
certificate fingerprint in the controller; it is not a claim of publisher
authenticity or safety.
