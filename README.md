# Fire TV Stick 4K (Mantis): temporary root and debloat

This project is for the **Fire TV Stick 4K `mantis/AFTMM` only**—not the 4K
Max. The scripts require Fire OS build `NS6711`, incremental
`0011644900484`, and the exact fingerprint and kernel listed in
[model safety](docs/MODEL-SAFETY.md). They stop on a mismatch. Do not try the
root patch or package list on another build.

The workflow uses **temporary, exec-only root**. It does not install `su` or
provide root after a reboot, and permits one exploit attempt per boot. The
package changes are reversible, so read the
[recovery guide](docs/RECOVERY.md) and keep its backup/journal files before
running anything.

## What it does

- Installs Wolf Launcher `0.1.9-Wolf` and Aurora Store `4.8.4` after checking
  their APKs.
- Reversibly disables 27 listed packages for user 0, plus Prime Video and
  shopping apps when installed. The root stage hides OTA,
  Appstore, the visible IMDb app, and stock Home-starter for user 0, then
  disables only the stock Home activity. System APKs are not deleted.
- Makes Wolf the Home launcher while keeping stock Settings, Wi-Fi, Bluetooth,
  remote-control services, the screensaver, and USB/network ADB available.
- Hides Wolf's empty Widgets section, its own tile, "What Should I Watch", and
  Prime tiles. When two Downloads tiles exist, it keeps the non-blue one.
- Preserves TiviMate, WireGuard, and Sweet TV when installed; it does not
  require or install missing ones.

The exact [Wolf Launcher 0.1.9-Wolf APK](assets/WolfLauncher_0.1.9-Wolf.apk)
is included for direct download. Its SHA-256 is
`d03ed56bb5564aa5b3e668831484917616510b02db4dde6a813d49a352054d05`.
The deployment script still fetches and independently verifies the same pinned
artifact from the original archive.

See the [package lists](manifests/) and [recovery guide](docs/RECOVERY.md) for
exact scope and rollback.

## 1. Build the temporary-root tool

On Ubuntu or Debian (Linux x86_64), run the host setup script:

```sh
git clone https://github.com/Delitants/firetv-mantis-standalone.git
cd firetv-mantis-standalone
scripts/setup-linux-host.sh
```

If you already cloned the repositories, run only the last two lines. The
script checks installed tools, asks **Y/N** before APT changes and the
[Android NDK r30](https://developer.android.com/ndk/downloads) download,
then asks whether to build the pinned GhostLock source. It does not run the
exploit or change the stick. The result is `../GhostLock/build/ghostlock_root`.
Read the
[exploit notes](exploit/README.md) and patched `README-MANTIS.md` before using
it. The upstream source is not redistributed here.

## 2. Run the guarded deployment

You need authorized **USB and network ADB connections to the same stick**, plus
`adb`, `curl`, `aapt`, `apksigner`, and Python 3 on the host. From the
`firetv-mantis-standalone` directory, replace the placeholders below:

First, connect the stick to the host by USB and list ADB devices:

```sh
adb devices -l
```

Find the row that says `device` and contains `usb:`. Copy its first field as
`USB_SERIAL`. Do not use an `IP:5555` row or a row marked `unauthorized`.

Next, find the stick's Wi-Fi IP over USB:

```sh
adb -s USB_SERIAL shell getprop dhcp.wlan0.ipaddress
```

If that prints nothing, find the IP in Fire TV Settings > Network or your
router's device list. The network ADB serial is this IP followed by `:5555`.
Connect it and confirm that both the USB row and the `IP:5555` row say
`device`:

```sh
adb connect DEVICE_IP:5555
adb devices -l
```

Use those two values in the deployment command below. The script stops before
app installation if USB is missing or a protected core package such as
`com.amazon.dp.logger` is not enabled; restore that package's baseline before
trying deployment.

Create your private backup directory first. The script rejects missing,
relative, and example output paths before contacting the stick:

```sh
mkdir -p "$HOME/firetv-mantis-backups"
```

```sh
scripts/deploy-mantis.sh \
  --serial USB_SERIAL \
  --network-serial DEVICE_IP:5555 \
  --root-binary ../GhostLock/build/ghostlock_root \
  --output "$HOME/firetv-mantis-backups" \
  --yes
```

The script checks the exact device, both ADB connections, and the exec-only
root binary before changing packages. It creates an audit and recovery backup,
deploys the apps and debloat, reboots, then checks Home, Settings, protected
apps, Wi-Fi, Bluetooth, and ADB again. It prints the live log path and
`PHASE=...` as it works; individual ADB calls and downloads are time-limited.
A Settings check can still take a few minutes, while package changes print
`APPLY_PROGRESS`. **Keep the private output directory:** restoring protected
changes requires its root-action journal and another temporary-root session.
See [recovery](docs/RECOVERY.md) if any check fails.
If rollback reports an incomplete backup, keep that directory and use its
`restore-user0.sh` once both ADB connections work. Do not rerun deployment over
the partial state. For example:

```sh
SERIAL=USB_SERIAL NETWORK_SERIAL=DEVICE_IP:5555 \
  "$HOME/firetv-mantis-backups/deployment-TIMESTAMP/debloat-backup/restore-user0.sh"
```

The post-reboot check proves the Android Home intent opens Wolf. ADB key
injection does not reproduce this model's physical remote Home button, so
test that button directly before relying on it.

## Optional Settings tile

The deployment script does **not** install the separate Settings tile. Its
[source and build/sign instructions](settings-tile/README.md) are provided for
Wolf Launcher users who want a direct tile for the stock Fire TV Settings
screen. The default label is English; Ukrainian is an optional locale
translation. No signed APK or signing key is published here.
