# AirPod Fitness

Apps that use AirPods head motion as a body sensor.

| App | Status | Idea |
| --- | --- | --- |
| [Heads Up!](apps/air-posture) (folder and bundle ID keep the old Air Posture name) | In App Review prep, [listing](docs/app-store/listing.md) | Notice when your head drops forward and give graded audio feedback; remind you to move after long stillness. |
| RepSense | idea (#4) | Count reps (push-ups, squats, pull-ups) from head motion, optionally fused with Apple Watch. |

Questions and answers: [docs/faq](docs/faq/README.md). Design notes: [docs/design.md](docs/design.md). Earlier conversations that led here: [docs/prior-conversations](docs/prior-conversations). Position recordings and their analysis: `data/recordings`, `tools/analyze_positions.py`.

## Run Heads Up!

Needs a real iPhone and motion-capable AirPods (Pro, 3rd gen or later, Max, Beats Fit Pro); the simulator has no headphone motion.

```bash
cd apps/air-posture
xcodegen generate
open AirPosture.xcodeproj   # pick your iPhone, Run
```

Testers normally install from TestFlight instead. Settings → Diagnostics shows the background, sound and AirPod state; the Record button runs the guided position recorder, whose exported CSV goes in `data/recordings`.

## TestFlight

A push to `main` that touches `apps/air-posture` archives the app and uploads it to TestFlight (`.github/workflows/testflight.yml`), and the Actions tab can run it by hand. The internal group "Luis" gets every build. The run goes green only once Apple has finished processing the build, so green means App Store Connect accepted it.

App 6830647347 in App Store Connect, bundle `lucharo.airposture`. The build number comes from App Store Connect (`tools/asc.py next-build`, one above the latest upload), so nothing is committed for it. The version is `MARKETING_VERSION` in `apps/air-posture/project.yml`, and it must match the App Store version.

The App Store Connect API key cannot cloud-sign, so CI signs manually: `apps/air-posture/tools/AppStore.xcconfig` and `ExportOptions-manual.plist`, the "Air Posture App Store" profile fetched from the API on each run, and the Apple Distribution certificate from repository secrets. `scripts/ci-testflight-secrets.sh` loads those secrets from the login keychain and `~/.appstoreconnect`; run it again when the certificate or key is renewed. This repo is private, so each macOS minute counts ten times against the plan, which is why the wait for Apple runs on Linux.

`tools/asc.py` is also a small App Store Connect API client on the same key. The key's role can read, upload and manage TestFlight, but it gets 403 on App Store listing writes, bundle IDs and profile creation. `tools/brave-js.sh` and `tools/brave-page-js.sh` drive a signed-in Brave over Apple Events for the web-only steps (Brave: View > Developer > Allow JavaScript from Apple Events).
