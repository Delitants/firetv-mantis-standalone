# Fire TV Stick 4K (Mantis): temporary root and debloat

This project is for the **Fire TV Stick 4K `mantis/AFTMM` only**—not the 4K
Max. The scripts require Fire OS build `NS6711`, incremental
`0011644900484`, and the exact fingerprint and kernel listed in
[model safety](docs/MODEL-SAFETY.md). They stop on a mismatch. Do not try the
root patch or package list on another build.

The workflow uses **temporary, exec-only root**. It does not install `su` or
provide root after a reboot, and permits one exploit attempt per boot. Package
changes persist, so read the
[recovery guide](docs/RECOVERY.md) and keep its backup/journal files before
running anything.

## What it does

- Installs Wolf Launcher `0.1.9-Wolf` and Aurora Store `4.8.4` after checking
  their APKs.
- Reversibly disables 30 listed packages for user 0. The root stage also
  disables OTA, Appstore, the visible IMDb app, and stock Home components.
  System APKs are not deleted.
- Makes Wolf the Home launcher while keeping stock Settings, Wi-Fi, Bluetooth,
  remote-control services, and USB/network ADB available.
- Leaves TiviMate, WireGuard, and Sweet TV untouched.

The exact [Wolf Launcher 0.1.9-Wolf APK](assets/WolfLauncher_0.1.9-Wolf.apk)
is included for direct download. Its SHA-256 is
`d03ed56bb5564aa5b3e668831484917616510b02db4dde6a813d49a352054d05`.
The deployment script still fetches and independently verifies the same pinned
artifact from the original archive.

See the [package lists](manifests/) and [recorded deployment
state](docs/DEPLOYED-STATE.md) for exact scope and verification limits.

## 1. Build the temporary-root tool

On a host with Android NDK r30, clone this repository and the pinned GhostLock
source side by side:

```sh
git clone https://github.com/Delitants/firetv-mantis-standalone.git
git clone --branch 4.4 https://github.com/R0rt1z2/GhostLock.git
cd GhostLock
git checkout 2e73c256ff0205de6d08ea0996d15f4700e23fdc
git am ../firetv-mantis-standalone/exploit/patches/0001-feat-add-exact-Mantis-exec-only-root-port.patch
make NDK=/absolute/path/to/android-ndk-r30 API=24
```

The result is `GhostLock/build/ghostlock_root`. Read the
[exploit notes](exploit/README.md) and patched `README-MANTIS.md` before using
it. The upstream source is not redistributed here.

## 2. Run the guarded deployment

You need authorized **USB and network ADB connections to the same stick**, plus
`adb`, `curl`, `aapt`, and `apksigner` on the host. From the
`firetv-mantis-standalone` directory, replace the placeholders below:

```sh
scripts/deploy-mantis.sh \
  --serial USB_SERIAL \
  --network-serial DEVICE_IP:5555 \
  --root-binary ../GhostLock/build/ghostlock_root \
  --output /path/to/private-backup \
  --yes
```

The script checks the exact device and both ADB connections before changing
packages. It creates an audit and recovery backup, deploys the apps and
debloat, reboots, then checks Home, Settings, protected apps, Wi-Fi, Bluetooth,
and ADB again. **Keep the private output directory:** restoring protected
changes requires its root-action journal and another temporary-root session.
See [recovery](docs/RECOVERY.md) if any check fails.

## Optional Settings tile

The deployment script does **not** install the separate Settings tile. Its
[source and build/sign instructions](settings-tile/README.md) are provided for
Wolf Launcher users who want a direct tile for the stock Fire TV Settings
screen. The default label is English; Ukrainian is an optional locale
translation. No signed APK or signing key is published here.
