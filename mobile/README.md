# /mobile: Ventrafin Android app (Flutter)

Android only. Package `com.ventrafin.app` (DECISIONS.md D10). Riverpod + go_router (D11). Auth and lock design: D12 and ARCHITECTURE.md § 5–6.

## Build-time config (never committed)

The app reads its settings at build time from `config/dev.json`, which is gitignored. Copy the template and fill it in:

```powershell
Copy-Item config\example.json config\dev.json   # then edit the three values
```

| Key | Where to find it |
|---|---|
| `SUPABASE_URL` | Supabase dashboard → Project Settings → API (`https://<ref>.supabase.co`) |
| `SUPABASE_PUBLISHABLE_KEY` | Same page. The **publishable** (`sb_publishable_…`) key, never a secret/service_role key |
| `GOOGLE_WEB_CLIENT_ID` | Google Cloud → Google Auth Platform → Clients → the **Web** client's ID |

A build without these shows a "setup needed" screen instead of the app.

## Run / build (from `mobile/`)

```powershell
flutter pub get
flutter devices                                              # phone connected with USB debugging?
flutter run --dart-define-from-file=config/dev.json          # debug build on the phone
flutter test                                                 # unit + widget tests
flutter build apk --release --dart-define-from-file=config/dev.json
```

Google Sign-In only works on a build whose signing key's SHA-1 is registered in an Android OAuth client (see the root setup notes). Debug builds use `%USERPROFILE%\.android\debug.keystore`. Release builds use the key in `android/key.properties` (gitignored); if that file is missing, they fall back to the debug key.

Get the SHA-1s with:

```powershell
cd android; .\gradlew signingReport
```

## Layout

```
lib/
  main.dart, app.dart, router.dart   bootstrap, theme, routes and redirects
  config/        build-time config
  core/          money (paise <-> ₹, Indian grouping), India time, errors, theme, offline banner,
                 category icons/palette (mirror of /shared/category-style.json), merchant badges, badge widgets
  data/          models, repository (Supabase), Riverpod providers, Realtime -> revisions
  features/
    auth/        native Google Sign-In -> signInWithIdToken
    lock/        pattern pad, PBKDF2 hashing, lock store/controller, lock overlay, setup
    entry/       keypad-first Add (batch) and Edit forms
    transactions/  month list grouped by date, delete, live updates
    categories/  category list + rename / icon / colour editor
    dashboard/   spending-by-category donut and table
    shell/ settings/  bottom nav, dashboard, More, placeholders, settings
test/            money, pattern-hash and category-style unit tests; add-flow and screen widget tests
                 (support/fake_repository.dart is the shared in-memory repository)
```

Screens set FLAG_SECURE (DECISIONS.md D15), so `adb screencap` and screen mirroring show black on a real device.
