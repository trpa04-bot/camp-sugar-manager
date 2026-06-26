GitHub Actions in this project use the Firebase Hosting workflow in `.github/workflows/firebase-hosting.yml`.

Required repository secret:

- `FIREBASE_SERVICE_ACCOUNT_CAMP_SUGAR_MANAGER`

How to create it:

1. In Firebase project `camp-sugar-manager`, open Google Cloud Console.
2. Create or select a service account that can deploy Firebase Hosting.
3. Generate a JSON key for that service account.
4. In GitHub repository settings, open `Settings > Secrets and variables > Actions`.
5. Add a new repository secret named `FIREBASE_SERVICE_ACCOUNT_CAMP_SUGAR_MANAGER`.
6. Paste the full JSON key as the secret value.

Behavior:

- Pull requests to `main` create Firebase Hosting preview deploys.
- Pushes to `main` deploy `build/web` to the live Firebase Hosting site.