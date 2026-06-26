# Firestore Backup and Recovery Runbook

## Environment
- Project ID: `camp-sugar-manager`
- Production database: `(default)`
- Recovery database: `recovery-20260623`
- Recovery bucket: `gs://camp-sugar-recovery-20260623`

Do not write secrets into this repository.

## Verify PITR status
Read-only command:

```bash
firebase firestore:databases:get --project camp-sugar-manager "(default)"
```

Expected field:
- `Point In Time Recovery: POINT_IN_TIME_RECOVERY_ENABLED`

## Verify scheduled backups
Read-only command:

```bash
firebase firestore:backups:schedules:list --project camp-sugar-manager --database "(default)"
```

If empty, create schedules only after explicit approval.

## Manual export before risky changes
Use the safe script:

```bash
./scripts/firestore_safe_export.sh
```

Script behavior:
- Uses project `camp-sugar-manager`
- Uses database `(default)`
- Creates UTC timestamped path under:
  - `gs://camp-sugar-firestore-backups/manual/YYYY/MM/DD/TIMESTAMP/`
- Fails if export does not complete successfully
- Prints operation ID and output URI
- Never deletes previous exports
- Never runs import automatically

## Check export operation status
If you have operation name:

```bash
gcloud firestore operations describe OPERATION_NAME --project=camp-sugar-manager --database="(default)"
```

## Restore procedure (safe path)
Always restore into a separate recovery database first, never directly into production.

1. Choose source backup/export.
2. Restore into a recovery database (for example `recovery-20260623`).
3. Validate data integrity in recovery database.
4. Compare with production expectations.
5. Promote only after explicit approval and validation.

## Incident procedure
1. Freeze destructive actions.
2. Confirm current PITR and backup status (read-only).
3. Export current state before any risky operation.
4. Perform recovery into a recovery database first.
5. Validate records, indexes, and app behavior.
6. Plan production cutover with rollback plan.

## Forbidden destructive commands without explicit approval
- `firebase firestore:delete`
- `gcloud firestore bulk-delete`
- delete with `--all-collections`
- delete with `--recursive`
- delete with `--force`
- deleting Firestore database
- deleting Cloud Storage buckets
- `rm -rf`
- `git reset --hard`
- `git clean -fd`

Required confirmation phrase before destructive actions:
- `POTVRĐUJEM BRISANJE`

## Protected recovery artifacts
Do not delete or modify without explicit approval:
- `recovery-20260623`
- `gs://camp-sugar-recovery-20260623`
- `before-delete-1440`
