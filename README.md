# camp_sugar_manager

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## GitHub Deploy

This repository now includes a GitHub Actions workflow for Firebase Hosting:

- pull requests to `main` create preview deploys
- pushes to `main` deploy the Flutter web build to live hosting

Before it can run, add the repository secret:

- `FIREBASE_SERVICE_ACCOUNT_CAMP_SUGAR_MANAGER`

See [.github/README.md](.github/README.md) for setup details.
