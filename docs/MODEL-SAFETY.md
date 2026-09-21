# Model and safety boundary

The only mutation target is Amazon `mantis/AFTMM`, build `NS6711`, incremental
`0011644900484`, Android `7.1.2` / API `25`, `armeabi-v7a`, `armv7l`, shell UID
`2000`, SELinux Enforcing. Every mutating controller command validates those
facts first.

`ROOT=NOT_ACHIEVED` is a required boundary. There is no root, bootloader,
BootROM, RPMB, recovery, partition, image, or `/system` operation here. The
controller only uses `pm uninstall -k --user 0` after an audit and a
help-proven `install-existing` rollback form.

Never remove, disable, clear, reinstall, or update the protected user apps:
`ar.tvplayer.tv`, `com.wireguard.android`, and `tv.sweet.tvplayer`. Preserve
Bluetooth, stock Home and Settings, input, DIAL, SSDP, Whisper services,
`tcomm`, `dp.logger`, and the Fire TV remote path.

USB configuration containing `adb` and network ADB on TCP 5555 are separate
checks. A USB property does not prove a physical cable/interface. Physical USB
was independently observed on the target as the exact AFTMM ADB interface; a
network-only verifier deliberately reports physical enumeration as unverified
rather than inferring it.
