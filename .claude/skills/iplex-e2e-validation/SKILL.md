---
name: iplex-e2e-validation
description: Validate iPlex Gestor changes end to end (Flutter, Firebase emulators, callable scenarios, TV pairing without a physical TV). Use before declaring any account, family, device or IPTV change complete.
---

# iPlex end-to-end validation

Business rules live in `AGENTS.md` (sections 1–13). This skill only lists the
verifiable steps; run them in order and report real output.

## 1. Static and unit
```bash
flutter analyze
flutter test
npm --prefix functions run check
```

## 2. Rules + backend integration (isolated emulators)
Do not run while a `firebase emulators:start` with Functions is up: its triggers
race the tests.
```bash
firebase emulators:exec --only auth,firestore,storage --project demo-iplex "npm --prefix functions run test:rules && npm --prefix functions run test:integration"
```

## 3. Callable scenarios over HTTP (A individual, B/C families, D pairing)
```bash
firebase emulators:start --only auth,firestore,functions,storage --project demo-iplex
npm --prefix functions run e2e:callable
```
Needs `functions/.secret.local` with `IPTV_CREDENTIAL_KEY=<base64 32 bytes>`
(gitignored, emulator only). Scenario A syncs a public M3U from the internet.

## 4. TV pairing without a TV
```bash
cd functions && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 GCLOUD_PROJECT=demo-iplex npm run dev:pairing-qr -- create --wait
```
Prints the manual code and writes `build/dev-pairing/pairing-qr.png`. `cleanup`
removes simulated TVs.

## 5. Gestor against emulators
```bash
flutter run -d <device> --dart-define=USE_EMULATORS=true --dart-define=FIREBASE_PROJECT_ID=demo-iplex --dart-define=EMULATOR_TEST_SIGN_IN=true
```
Debug iOS builds must be launched by `flutter run` (a bare install does not start).
The simulator has no camera: use the manual code path for pairing.

## 6. Cross-project (Control ↔ iPlex Web ↔ Samsung shell)
Run the emulators with both codebases (Control `functions/` + iPlex Web
`functions/`, hosts `0.0.0.0`), the Web with `vite --mode emulator` (browser)
or `vite build --mode emulator` served on the LAN with CORS on
`/iplex-web.json` (TV: `npm run tv -- --env development --target http://<mac>:5050/`
in the App repo). Then drive the phone side:
```bash
cd functions && npx tsx scripts/e2e_tv.ts setup
npx tsx scripts/e2e_tv.ts tvcode          # code shown by the TV
npx tsx scripts/e2e_tv.ts link <code>
npx tsx scripts/e2e_tv.ts play "<title>"  # follows pending → delivered → started
npx tsx scripts/e2e_tv.ts unlink
```
Restore the TV to production afterwards (`npm run tv` in the App repo).

## Reporting
Classify each flow as validated, implemented-without-external-validation, or
blocked; never mark a scenario validated that was not executed.
