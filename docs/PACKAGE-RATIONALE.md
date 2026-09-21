# Package rationale

The removal manifest is deliberately small and is validated against the
preservation manifests before any action. Packages not explicitly listed are
not candidates for removal.

The preservation lists cover stock Settings and its dependencies, Home,
Bluetooth/input, networking, DIAL/SSDP, Whisper services, package installation,
and recovery support. The three protected user applications are preserved even
when a generic package category might otherwise make them appear removable.

Wolf Launcher is pinned to version code `11900120` and version name
`0.1.9-Wolf`, package `com.wolf.firelauncher`, and its launcher activity. An
installed `0.1.7-FireTV` does not satisfy the verification gate. Artifact
provenance is limited to the recorded archive URL, fixed SHA-256, and signer
certificate fingerprint in the controller; it is not a claim of publisher
authenticity or safety.
