#!/usr/bin/env bash
# Human-in-the-loop embedded reproduction and evidence capture template.
# Copy this file, replace the placeholders, and run it from a safe test setup.
# The script does not flash, reset, or power-cycle hardware by default.

set -euo pipefail

step() {
  printf '\n>>> %s\n' "$1"
  read -r -p "    [Press Enter when complete] " _
}

capture() {
  local var="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p "    > " answer
  printf -v "$var" '%s' "$answer"
}

# Edit the setup, trigger, and evidence steps for the target. Keep hazardous
# outputs disabled and do not clear reset/fault state before it is captured.
step "Place the target in the documented safe test state and connect the required probe or instruments."
step "Confirm the board revision, firmware build ID, power conditions, and test configuration."
step "Capture reset cause and any retained crash record before reflashing or resetting."
step "Apply the documented trigger once while recording target logs and external measurements."

capture OBSERVED "Was the exact target symptom observed? (yes/no/uncertain)"
capture ARTIFACTS "List saved logs, dumps, traces, captures, and instrument files:"
capture NOTES "Record timing, reset reason, visible hardware state, and anything unusual:"

printf '\n--- Captured ---\n'
printf 'OBSERVED=%s\n' "$OBSERVED"
printf 'ARTIFACTS=%s\n' "$ARTIFACTS"
printf 'NOTES=%s\n' "$NOTES"

