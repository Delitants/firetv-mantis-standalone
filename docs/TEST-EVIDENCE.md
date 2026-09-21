# Test-evidence schema

Public evidence is deliberately redacted. It records command outcomes and
stable component identities, never connection data, screenshots, XML dumps,
APKs, backups, or VPN material.

| Field | Meaning |
| --- | --- |
| `PACKAGE_OPERATION=pm disable-user --user 0` | Help-proven reversible per-user disable mode. |
| `PACKAGE_RESTORE=pm enable --user 0` | Help-proven inverse used only for recorded successful disables. |
| `VERIFY_GATE=PASS` | Exact target and preservation checks passed. |
| `SETTINGS_ROUTES=PASS` | Every action produced one strictly parsed stock component matching the checksummed ten-route baseline. |
| `ADB_PERSISTENCE=PASS` | ADB Debugging, null Developer Options baseline, adbd, USB configuration, TCP port, and TCP transport passed. |
| `TCP8009=PASS` | A listener was observed. This is not remote-control proof. |
| `NETWORK_REMOTE_OBSERVED=UNVERIFIED` | No non-ADB remote UI movement was captured. |
| `USB_PHYSICAL_ENUMERATION=UNVERIFIED` | Generic verifier result; never infer enumeration from a property. |
| `UI_SMOKE=PASS` | Focused stock Settings components and non-empty UI hierarchies were observed. |
| `UKRAINIAN_LOCALE=UNAVAILABLE` | Observed stock Language list did not offer Ukrainian; no locale selection occurred. |

Observed live facts are distinct from controller inference: the physical USB
interface was directly observed as AFTMM ADB, while `development_settings_enabled`
was null even though Developer Options and its ADB toggle were accessible.
Accessibility, Display & Sounds, Preferences/Date & Time, and Language rendered
through stock-menu D-pad navigation after the expected launcher permission
denial. Wolf `0.1.9-Wolf` was installed and headlessly rendered, but no
debloat/reboot acceptance is recorded here.

Package tests use the enabled inventory as the operative set and require each
successful candidate to move into the disabled inventory. They cover missing
help syntax, already-disabled skips, silent no-effect rejection, interruption
between disable and journal success, reverse restore, partial enable failure,
interruption after enable but before ledger pruning, an enable that mutates
state while returning nonzero, post-enable guard failure, checksum/tamper
rejection, and the exact 32-entry candidate manifest. These are controller
tests, not a claim that a live package transition or reboot passed. The same
full suite is exercised with the local default `sh` and `/bin/dash`. Generated
recovery is tested as a resumable controller entry point, including checksum and
mode binding, manifest membership, disabled-before/enabled-after state, and
idempotent completion after the ledger is empty.

Resolver tests cover legacy one-line output and production-shaped Fire OS
metadata plus component output. Raw Settings resolver evidence is kept separate
from the parsed baseline. Missing, ambiguous, malformed, foreign-action, and
foreign-component output is rejected, and Settings route drift is exercised
after disable, after rollback enable, and during fresh restore.

The smoke verifier parses only the current-focus field, waits in bounded steps
for asynchronous Launcher activity changes, and cleans its temporary hierarchy
file before backing out to Home on every failed route. Stock-menu events are
paced; an independent `--network-serial` is required when the primary serial is
USB. The controller compares the two transports' nonempty device identities in
memory without publishing them. Its checksummed baseline preserves the exact
persisted ADB TCP-port state (including an empty value); only the runtime TCP
listener is required to use port 5555.
