# Security policy

Report suspected repository vulnerabilities privately to the maintainer before
publishing details. Do not include device identifiers, network addresses,
credentials, backups, APKs, VPN configuration, or account data in a report.

This repository rejects BootROM, partition, recovery, and `/system`
modification techniques. Its temporary-root path is limited to one exact Fire
OS build, is exec-only, keeps SELinux Enforcing, and has no persistent command
service. Every mutation remains behind fail-closed identity and preservation
checks.

Before publication, run `sh tests/scan-excluded-content.sh .` and keep its
result clean.
