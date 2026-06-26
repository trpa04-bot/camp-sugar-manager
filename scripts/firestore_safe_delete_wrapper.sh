#!/usr/bin/env bash
set -euo pipefail

# Safety-first wrapper for Firestore delete operations.
# Defaults to emulator-only dry-run and refuses production by default.

PROJECT_ID="${FIREBASE_PROJECT_ID:-camp-sugar-manager}"
DATABASE_ID="${FIRESTORE_DATABASE_ID:-}"
TARGET_PATH="${1:-}"
DRY_RUN="${DRY_RUN:-1}"
USE_FORCE="${USE_FORCE:-0}"
ALLOW_PRODUCTION_DELETE="${ALLOW_PRODUCTION_DELETE:-0}"

if [[ -z "${TARGET_PATH}" ]]; then
  echo "Usage: FIRESTORE_DATABASE_ID=<db> ./scripts/firestore_safe_delete_wrapper.sh <path>" >&2
  exit 1
fi

if [[ -z "${DATABASE_ID}" ]]; then
  echo "FIRESTORE_DATABASE_ID is required." >&2
  exit 1
fi

if [[ -z "${FIRESTORE_EMULATOR_HOST:-}" ]]; then
  echo "Refusing delete: FIRESTORE_EMULATOR_HOST is not set." >&2
  echo "This wrapper defaults to emulator-only execution." >&2
  exit 1
fi

if [[ "${PROJECT_ID}" == "camp-sugar-manager" && "${ALLOW_PRODUCTION_DELETE}" != "1" ]]; then
  echo "Refusing delete against production project ${PROJECT_ID}." >&2
  echo "Set ALLOW_PRODUCTION_DELETE=1 only after explicit human approval." >&2
  exit 1
fi

CMD=(firebase firestore:delete "${TARGET_PATH}" "--project=${PROJECT_ID}" "--database=${DATABASE_ID}")

# Recursive is optional and must be explicit.
if [[ "${RECURSIVE_DELETE:-0}" == "1" ]]; then
  CMD+=(--recursive)
fi

# Never use --force automatically. Must be explicitly requested.
if [[ "${USE_FORCE}" == "1" ]]; then
  CMD+=(--force)
fi

echo "Prepared command: ${CMD[*]}"
echo "Project: ${PROJECT_ID}"
echo "Database: ${DATABASE_ID}"
echo "Target path: ${TARGET_PATH}"
echo "Dry-run: ${DRY_RUN}"

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "Dry-run only. No deletion executed."
  exit 0
fi

"${CMD[@]}"
