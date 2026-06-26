# Camp Sugar Manager Agent Safety Rules

These rules are mandatory for all coding agents operating in this repository.

## Non-negotiable destructive command policy

Never execute destructive Firebase, Git, or shell commands without explicit user approval.

Forbidden without approval:
- `firebase firestore:delete`
- `gcloud firestore bulk-delete`
- any delete command with `--all-collections`
- delete flows using `--recursive`
- delete flows using `--force`
- deleting Firestore databases
- deleting Cloud Storage buckets
- `rm -rf`
- `git reset --hard`
- `git clean -fd`
- seed/migration scripts that overwrite or delete existing production data

Before any destructive command, you MUST:
1. Show the exact command.
2. State project ID and database ID.
3. Explain exactly what will be deleted.
4. Provide impact assessment.
5. Offer a safer alternative.
6. Verify a recent backup/export exists.
7. Request this exact confirmation phrase from the user: `POTVRĐUJEM BRISANJE`.

Without the exact phrase `POTVRĐUJEM BRISANJE`, do not execute the command.

## Firestore safety defaults

- Production project ID: `camp-sugar-manager`
- Production database ID: `(default)`
- Recovery database ID: `recovery-20260623`
- Recovery bucket (do not modify): `gs://camp-sugar-recovery-20260623`

Rules:
- Keep PITR enabled for `(default)`.
- Do not run imports/restores directly into production without explicit approval.
- Test cleanup/delete scripts must default to emulator-only execution.

## Recovery artifacts protection

Do not delete or modify these artifacts unless explicitly approved:
- `recovery-20260623`
- `gs://camp-sugar-recovery-20260623`
- `before-delete-1440` export artifact
