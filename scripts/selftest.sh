#!/usr/bin/env bash
# Runs CopyVisible's built-in self-test (debug builds only) and prints the
# results. It reads pictures it draws itself, so it needs no Screen
# Recording, then tries smart actions if Apple Intelligence is on.
set -euo pipefail
LOG="$HOME/Library/Logs/CopyVisible/copyvisible.log"
start=$(wc -l < "$LOG" 2>/dev/null || echo 0)
/usr/bin/swift - <<'SWIFT'
import Foundation
DistributedNotificationCenter.default().postNotificationName(
  Notification.Name("com.barrynapier.copyvisible.selftest"), object: nil, userInfo: nil, deliverImmediately: true)
SWIFT
for _ in $(seq 1 180); do
  sleep 1
  if tail -n +"$((start + 1))" "$LOG" | grep -qE "SELFTEST (PASS|FAIL [0-9]+ check)"; then break; fi
done
tail -n +"$((start + 1))" "$LOG" | grep -E "SELFTEST" | cut -c15-
