# Optional Settings tile

Wolf Launcher 0.1.9 does not expose this Fire OS build's full Settings root as
an app tile. Its generic Android Settings command opens a dummy handler. The
top-level HUD also requires the privileged `INSTALL_PACKAGES` permission.

This small app has no permissions or services. Its launcher activity starts
the exported stock `com.amazon.tv.launcher/.ui.MainSettingsActivity` with
`FLAG_ACTIVITY_CLEAR_TOP`, then finishes. The stock Home component can remain
disabled. The default label is English; `values-uk` supplies the Ukrainian
label on Ukrainian devices.

Build with Apktool 2.11.1 or a compatible version:

```sh
apktool b settings-tile -o /tmp/mantis-settings-tile-unsigned.apk
```

Sign the APK with your own private key. Keep the same key for updates; neither
an APK nor a signing key is distributed by this repository. For example:

```sh
keytool -genkeypair -alias mantis-settings-tile -keyalg RSA -keysize 2048 \
  -validity 3650 -keystore /private/path/settings-tile.jks \
  -dname 'CN=Mantis Settings Tile'
jarsigner -keystore /private/path/settings-tile.jks \
  -signedjar /tmp/mantis-settings-tile.apk \
  /tmp/mantis-settings-tile-unsigned.apk mantis-settings-tile
jarsigner -verify /tmp/mantis-settings-tile.apk
```

Install over the already authorized ADB transport, then select the new tile
from Wolf Home. The resulting foreground activity must be
`com.amazon.tv.launcher/.ui.MainSettingsActivity`, with Network, Applications,
Controllers & Bluetooth Devices, and My Fire TV visible. Verify those pages
through the tile before relying on it.

Hiding the Downloads tiles in Wolf does not disable either Downloads package.
Fire TV Settings → Applications → Manage Installed Applications still opens the
Downloads app information page. That page does not offer a Launch button or
file browsing; unhide a Downloads tile or use a file manager when you need to
open downloaded files.
