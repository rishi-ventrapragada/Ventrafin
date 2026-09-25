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
dart run tool/gen_theme_tokens.dart                          # after editing /shared/theme-tokens.json
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
  core/          money (paise <-> ₹, Indian grouping), India time, errors, offline banner, month bar,
                 theme (six themes; theme_tokens.g.dart is generated from /shared/theme-tokens.json),
                 category icons/palette/glyph rules (mirror of /shared/category-style.json),
                 merchant badges, badge widgets
  data/          models, repository (Supabase), Riverpod providers, Realtime -> revisions
  features/
    auth/        native Google Sign-In -> signInWithIdToken
    lock/        pattern pad, PBKDF2 hashing, lock store/controller, lock overlay, setup
    entry/       keypad-first Add (batch) and Edit forms
    transactions/  month list grouped by date, delete, live updates
    categories/  category list + rename / icon / colour editor
    dashboard/   spending-by-category donut and table
    reports/     any month by category, 6/12-month income-vs-spending and category trends (fl_chart + tables)
    bills/       bills list with due status, add/edit form, "Mark paid" sheet
    reminders/   reminder plan (pure), flutter_local_notifications wrapper, sync provider, permission prompt
    shell/ settings/  bottom nav, dashboard, More; settings (reminders, theme, your data: CSV export
                 via the share sheet, app lock, sign out); export_range.dart mirrors the web's presets
tool/            gen_theme_tokens.dart
test/            money, pattern-hash, category-style, theme (contrast on all six themes), reminder-plan and export
                 unit tests; add-flow, screen and large-text layout widget tests
                 (support/fake_repository.dart is the shared in-memory repository)
```

Screens set FLAG_SECURE (DECISIONS.md D15), so `adb screencap` and screen mirroring show black on a real device.

## Reminders (phase 6)

Scheduled on the phone with `flutter_local_notifications`, in Asia/Kolkata whatever the phone's time zone
(DECISIONS.md D24). Android permissions:
- **Notifications** (Android 13+): asked once, after a short explanation, the first time the app opens with a
  reminder switched on. If refused, Settings shows a banner; its **Allow** asks again, and once Android stops
  showing its prompt (after two refusals) it opens the app's notification settings instead.
- **Alarms & reminders** (exact timing, off by default on Android 14+): not required. Without it reminders are
  scheduled as inexact alarms and may arrive some minutes late; Settings says so and offers **Allow**.
- Reminders survive a reboot or an app update (boot receiver). Signing out cancels them all.
- Settings › **Send a test reminder** shows one straight away.
