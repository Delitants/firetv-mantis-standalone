# Fire TV Mantis Standalone

An intentionally narrow, recovery-first controller for the exact Amazon
`mantis/AFTMM` Fire OS target documented in `docs/MODEL-SAFETY.md`. It audits,
plans reversible user-zero package removals, verifies a pinned Wolf Launcher,
and refuses operations outside that boundary.

`ROOT=NOT_ACHIEVED`: this project has no root, partition, recovery, or system
image procedure. It does not change locale automatically. Do not add APKs,
backups, connection data, or credentials to this repository.

Start with an audit, read the generated restore script, run `--baseline AUDIT_DIRECTORY verify` (and `--network-serial SERIAL:5555` before it when the primary serial is USB), and use
`verify-settings` before any package action. The latter only opens stock
Settings routes and backs out; it never writes a setting. See
`docs/RECOVERY.md` before using `apply` or `restore`.

The project is English and locale-neutral. A stock Language-screen selection is
optional and manual; the observed target did not offer Ukrainian and records
`UKRAINIAN_LOCALE=UNAVAILABLE`.
