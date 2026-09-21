# Test-evidence schema

Public evidence is deliberately redacted. It records command outcomes and
stable component identities, never connection data, screenshots, XML dumps,
APKs, backups, or VPN material.

| Field | Meaning |
| --- | --- |
| `VERIFY_GATE=PASS` | Exact target and preservation checks passed. |
| `SETTINGS_ROUTES=PASS` | Every action resolved to the pinned stock component. |
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
