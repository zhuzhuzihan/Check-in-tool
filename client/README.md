# Remote Clock-in Client

Flutter 3.44 mobile client for the remote attendance service.

Run with demo data:

```sh
flutter pub get
flutter run
```

Connect to a backend:

```sh
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1 \
  --dart-define=AUTH_TOKEN=YOUR_DEVELOPMENT_TOKEN
```

`AUTH_TOKEN` is a local-development bootstrap mechanism, not a production login solution. A production app should obtain short-lived tokens through an identity flow and keep them in platform-secure storage.

See the repository root [`README.md`](../README.md), [`docs/design.md`](../docs/design.md), and [`docs/security.md`](../docs/security.md) for architecture, design, and security details.
