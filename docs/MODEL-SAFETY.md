# Model and safety boundary

The only mutation target is Amazon `mantis/AFTMM`, build `NS6711`, incremental
`0011644900484`, Android `7.1.2` / API `25`, `armeabi-v7a`, `armv7l`, shell UID
`2000`, SELinux Enforcing. Every mutating controller command validates those
facts first.

The exact-build root port is published under `exploit/` as a patch against its
upstream base. There is no bootloader, BootROM, RPMB, recovery, partition,
image, or `/system` operation here. The controller only uses
`pm disable-user --user 0` after an audit and
only when `pm help` proves both that form and the exact `pm enable --user 0`
inverse.
This is a package-manager state change for user 0, not erasure from the system
image. The completed live deployment used temporary root for protected
Home-component and OTA state; see `DEPLOYED-STATE.md`.

The released Mantis root path is exec-only, requires one staged action script,
allows one attempt per boot, leaves SELinux Enforcing, and exposes no root
daemon, bind shell, mounted `su`, or built-in OTA mutation. The profile is
literal-matched to the full product/model/fingerprint/incremental/kernel tuple.

Never remove, disable, clear, reinstall, or update the protected user apps:
`ar.tvplayer.tv`, `com.wireguard.android`, and `tv.sweet.tvplayer`. Preserve
Bluetooth, stock Home and Settings, input, DIAL, SSDP, Whisper services,
`tcomm`, `dp.logger`, and the Fire TV remote path.

USB configuration containing `adb` and network ADB on TCP 5555 are separate
checks. A USB property does not prove a physical cable/interface. Physical USB
was independently observed on the target as the exact AFTMM ADB interface; a
network-only verifier deliberately reports physical enumeration as unverified
rather than inferring it.
