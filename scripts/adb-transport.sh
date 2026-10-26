#!/bin/sh

require_usb_primary() {
  transport_adb=$1
  transport_serial=$2
  transport_network_serial=$3
  if [ -z "$transport_serial" ] || [ -z "$transport_network_serial" ] ||
    [ "$transport_serial" = "$transport_network_serial" ]
  then
    printf '%s\n' 'USB_PRIMARY_REJECTED primary and network ADB must use distinct serials' >&2
    return 1
  fi
  case "$transport_network_serial" in
    *:5555) ;;
    *) printf '%s\n' 'USB_PRIMARY_REJECTED network serial must end in :5555' >&2; return 1 ;;
  esac
  transport_script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  if ! transport_devices=$(python3 "$transport_script_dir/run-bounded.py" 15 "$transport_adb" devices -l < /dev/null); then
    printf '%s\n' 'USB_PRIMARY_REJECTED could not list ADB transports' >&2
    return 1
  fi
  if ! printf '%s\n' "$transport_devices" | awk -v serial="$transport_serial" '
    $1 == serial {
      matches++
      if ($2 == "device") {
        for (field = 3; field <= NF; field++) {
          if ($field ~ /^usb:[^[:space:]]+$/) usb = 1
        }
      }
    }
    END { exit (matches == 1 && usb) ? 0 : 1 }
  '; then
    printf '%s\n' 'USB_PRIMARY_REJECTED primary ADB must be one authorized USB device row in adb devices -l' >&2
    return 1
  fi
}
