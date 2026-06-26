#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="camp-sugar-manager"
BUCKET_NAME="camp-sugar-manager.firebasestorage.app"
CORS_FILE="$(cd "$(dirname "$0")" && pwd)/storage_cors.json"

GCLOUD_BIN="${GCLOUD_BIN:-$HOME/google-cloud-sdk/bin/gcloud}"

if [[ ! -x "${GCLOUD_BIN}" ]]; then
  echo "gcloud nije pronađen na: ${GCLOUD_BIN}" >&2
  echo "Instaliraj Google Cloud CLI ili postavi GCLOUD_BIN varijablu." >&2
  exit 1
fi

if [[ ! -f "${CORS_FILE}" ]]; then
  echo "Nedostaje CORS datoteka: ${CORS_FILE}" >&2
  exit 1
fi

ACTIVE_ACCOUNT="$(${GCLOUD_BIN} auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  echo "Nema aktivnog gcloud računa. Pokreni: ${GCLOUD_BIN} auth login" >&2
  exit 1
fi

echo "Primjenjujem CORS na bucket: gs://${BUCKET_NAME}"
${GCLOUD_BIN} storage buckets update "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" \
  --cors-file="${CORS_FILE}"

echo
echo "Aktivni CORS config:"
${GCLOUD_BIN} storage buckets describe "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" \
  --format='yaml(cors_config)'
