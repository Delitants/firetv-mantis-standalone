# Verified deployment state

This repository remains an English, locale-neutral controller for the exact
`mantis/AFTMM` target in `MODEL-SAFETY.md`. The following records the completed
live deployment without publishing device identifiers, network coordinates,
APKs, exploit material, backups, or screenshots.

## Applied state

- All 30 manifest candidates were disabled for user 0 and remained disabled
  after reboot. Their system APKs remain present, so the operation is
  reversible with the checksummed recovery ledger.
- `ar.tvplayer.tv`, `com.wireguard.android`, and `tv.sweet.tvplayer` remained
  installed, enabled, and unchanged.
- Wolf Launcher `0.1.9-Wolf` is the resolved Home activity after reboot.
- Only the two stock Home activities were disabled. The Amazon launcher package
  itself remains enabled so its Settings activities remain available.
- Aurora Store `4.8.4` was installed from the official Aurora OSS distribution
  after verifying its APK signature. The APK is not redistributed here.
- The three OTA packages, Amazon Appstore (`com.amazon.venezia`), and the
  visible IMDb application (`com.imdb.livingroom.firetv`) were disabled
  by the restorative root stage and remained disabled after reboot. The
  separate legacy IMDb package is part of the ordinary 30-package ledger.
- ADB remained enabled over USB configuration and TCP port 5555, and both
  transports were observed after reboot.
- The Android framework configuration reports `uk-UA`. This locale change was
  made outside this repository. Fire OS screens without Ukrainian resources
  continue to render their embedded English strings.
- A locally signed Settings tile built from `settings-tile/` was installed
  after the main deployment. It opens the exported stock Settings root from
  Wolf Home. The Wolf and two Downloads tiles were hidden in Wolf's layout;
  their packages and Download Manager remain enabled.
- After a further reboot, selecting the Settings tile again focused the stock
  `MainSettingsActivity`. Wolf remained Home, both ADB transports reconnected,
  and the hidden tiles remained absent from Home. The Settings Applications
  page opened the Downloads app information screen; it does not offer Launch.
- The Settings tile uses Wolf's Vertical tile appearance, placing its label on
  one line beneath the icon. Its APK source retains English as the default
  label and supplies Ukrainian only as an optional locale translation.
- The stock Live TV Settings card was hidden with the reversible
  `Settings.Secure` key `st_show_live_card=0`. After reboot it was absent from
  the stock Settings grid. Profiles, Alexa, and Help remain visible: this
  build's card producer has no comparable per-card visibility setting for
  them, and their packages were not disabled merely to alter the grid.

## Post-reboot acceptance

- Home resolves to and resumes Wolf Launcher.
- Every one of the 30 debloat candidates is still disabled.
- All 53 preserved packages are still enabled.
- All five protected user applications are still enabled.
- System Status Monitor (`com.amazon.ssm`) is part of the reversible user-0
  ledger. `com.amazon.vizzini.ftvcds` remains enabled for voice dependencies;
  its Wolf tile is a launcher-layout concern, not a package disable.
- All ten essential Settings routes resolve to their pinned stock components.
- The user-facing Settings HUD opens the stock Settings task and exposes
  Network, Applications, Controllers & Bluetooth Devices, My Fire TV,
  Preferences, and the remaining essential categories.
- Bluetooth is ON; Wi-Fi is enabled and connected.
- Whisper/tcomm packages are enabled and their services are running. This is
  service-preservation evidence, not a claim of an independently observed
  non-ADB remote-control event.
- SELinux is Enforcing. Temporary root is absent after reboot as expected; all
  intended package/component state persisted.

## Root-only recovery notes

The ordinary 30-package debloat is restored with the audit directory and
`scripts/mantis-tool.sh restore` as documented in `RECOVERY.md`.

Restoring the final launcher, OTA, Appstore, or visible IMDb state requires root
on this protected Fire OS build. Use `scripts/device-root-restore.sh` with the
original `root-actions.journal` and `root-actions.journal.md5`; it verifies the
journal and restores only package/component entries recorded as changed by that
deployment, in reverse order.

After restoring the Home activities, verify the Home resolver and stock
Settings routes before removing Wolf Launcher. Do not disable the entire
`com.amazon.tv.launcher` package: its Settings activities are deliberately
preserved.

To restore the Live TV card, set `st_show_live_card` to `1` with
`adb shell settings put secure st_show_live_card 1`, then reboot so the stock
card producer republishes the Settings grid.
