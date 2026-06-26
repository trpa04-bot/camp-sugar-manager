# Copilot Safety Instructions (Project Scope)

For repository `Camp Sugar Manager`, destructive operations require explicit user confirmation.

## Never run without explicit user approval
- `firebase firestore:delete`
- `gcloud firestore bulk-delete`
- delete commands with `--all-collections`
- delete commands with `--recursive`
- delete commands with `--force`
- deleting Firestore databases
- deleting Cloud Storage buckets
- `rm -rf`
- `git reset --hard`
- `git clean -fd`
- seed/migration scripts that delete or overwrite existing data

## Mandatory preflight before destructive command
1. Show exact command.
2. Show project and database ID.
3. Explain what gets deleted.
4. Provide impact assessment.
5. Offer a safer alternative.
6. Verify recent backup/export exists.
7. Request exact confirmation phrase: `POTVRĐUJEM BRISANJE`.

Without exact phrase `POTVRĐUJEM BRISANJE`, do not execute.

## Data protection defaults
- Keep PITR enabled for project `camp-sugar-manager`, database `(default)`.
- Recovery artifacts are protected:
  - `recovery-20260623`
  - `gs://camp-sugar-recovery-20260623`
  - `before-delete-1440`
- Never import directly into production before validation in recovery database.
