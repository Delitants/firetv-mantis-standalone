#!/bin/sh

# Extract an exact whitespace-delimited attribute from one aapt badging line.
apk_badging_value() {
  case "$2" in name|versionCode|versionName) ;; *) return 2 ;; esac
  printf '%s\n' "$1" | sed -n "s/.*[[:space:]]$2='\\([^']*\\)'.*/\\1/p" | head -n 1
}
