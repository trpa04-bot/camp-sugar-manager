#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${FIRESTORE_EMULATOR_HOST:-}" ]]; then
  echo "FIRESTORE_EMULATOR_HOST is not set. Aborting to protect production data." >&2
  exit 1
fi

echo "FIRESTORE_EMULATOR_HOST=${FIRESTORE_EMULATOR_HOST}"
