#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="camp-sugar-manager"
DATABASE_ID="(default)"
BACKUP_BUCKET="${FIRESTORE_BACKUP_BUCKET:-camp-sugar-firestore-backups}"
LOCATION="${FIRESTORE_BACKUP_LOCATION:-eur3}"

if [[ "${BACKUP_BUCKET}" == "camp-sugar-recovery-20260623" ]]; then
  echo "Refusing to use recovery bucket for routine exports: gs://${BACKUP_BUCKET}" >&2
  exit 1
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud is not installed. Cannot run manual export safely." >&2
  echo "Install Google Cloud CLI, then rerun this script." >&2
  exit 1
fi

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  echo "No active gcloud account found. Run: gcloud auth login" >&2
  exit 1
fi

if ! gcloud storage buckets describe "gs://${BACKUP_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Backup bucket does not exist or is inaccessible: gs://${BACKUP_BUCKET}" >&2
  echo "Proposed create command (DO NOT auto-run):" >&2
  echo "  gcloud storage buckets create gs://${BACKUP_BUCKET} --project=${PROJECT_ID} --location=${LOCATION} --uniform-bucket-level-access" >&2
  exit 1
fi

UTC_TS="$(date -u +%Y%m%dT%H%M%SZ)"
DATE_PATH="$(date -u +%Y/%m/%d)"
OUTPUT_URI="gs://${BACKUP_BUCKET}/manual/${DATE_PATH}/${UTC_TS}/"

echo "Starting Firestore export..."
echo "Project: ${PROJECT_ID}"
echo "Database: ${DATABASE_ID}"
echo "Output URI: ${OUTPUT_URI}"

OPERATION_NAME="$(gcloud firestore export "${OUTPUT_URI}" \
  --project="${PROJECT_ID}" \
  --database="${DATABASE_ID}" \
  --async \
  --format='value(name)')"

if [[ -z "${OPERATION_NAME}" ]]; then
  echo "Failed to obtain export operation name." >&2
  exit 1
fi

echo "Operation started: ${OPERATION_NAME}"

while true; do
  OP_JSON="$(gcloud firestore operations describe "${OPERATION_NAME}" \
    --project="${PROJECT_ID}" \
    --database="${DATABASE_ID}" \
    --format=json)"

  DONE="$(python3 - <<'PY' "${OP_JSON}"
import json, sys
obj = json.loads(sys.argv[1])
print('true' if obj.get('done') else 'false')
PY
)"

  if [[ "${DONE}" == "true" ]]; then
    HAS_ERROR="$(python3 - <<'PY' "${OP_JSON}"
import json, sys
obj = json.loads(sys.argv[1])
print('true' if 'error' in obj else 'false')
PY
)"

    if [[ "${HAS_ERROR}" == "true" ]]; then
      echo "Export operation finished with error." >&2
      python3 - <<'PY' "${OP_JSON}"
import json, sys
obj = json.loads(sys.argv[1])
print(json.dumps(obj.get('error', {}), indent=2))
PY
      exit 1
    fi

    break
  fi

  echo "Export in progress..."
  sleep 10
done

echo "Firestore export completed successfully."
echo "Operation ID: ${OPERATION_NAME}"
echo "Output URI: ${OUTPUT_URI}"
