# Security policy

Report suspected repository vulnerabilities privately to the maintainer before
publishing details. Do not include device identifiers, network addresses,
credentials, backups, APKs, VPN configuration, or account data in a report.

This repository rejects root, BootROM, partition, recovery, and `/system`
modification techniques. The intended security boundary is unprivileged ADB on
one exact Fire OS build, with fail-closed identity and preservation checks.

Before publication, run `sh tests/scan-excluded-content.sh .` and keep its
result clean.
