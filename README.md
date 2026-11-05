# AirPod Fitness

Apps that use AirPods head motion as a body sensor.

| App | Status | Idea |
| --- | --- | --- |
| [Air Posture](apps/air-posture) | TestFlight beta | Notice when your head drops forward and give graded audio feedback; remind you to move after long stillness. |
| RepSense | idea (#4) | Count reps (push-ups, squats, pull-ups) from head motion, optionally fused with Apple Watch. |

Questions and answers: [docs/faq](docs/faq/README.md). Design notes: [docs/design.md](docs/design.md). Earlier conversations that led here: [docs/prior-conversations](docs/prior-conversations). Position recordings and their analysis: `data/recordings`, `tools/analyze_positions.py`.

## Run Air Posture

Needs a real iPhone and motion-capable AirPods (Pro, 3rd gen or later, Max, Beats Fit Pro); the simulator has no headphone motion.

```bash
cd apps/air-posture
xcodegen generate
open AirPosture.xcodeproj   # pick your iPhone, Run
```

Testers normally install from TestFlight instead. Settings → Diagnostics shows the background, sound and AirPod state; the Record button runs the guided position recorder, whose exported CSV goes in `data/recordings`.

## TestFlight

Ship a build with `tools/ship-testflight.sh` from the repo root. The details below are what it automates.

App 6830647347 in App Store Connect, bundle `lucharo.airposture`, internal group "Luis". Build 1 uploaded 2026-11-04.

The App Store Connect API key in `~/.appstoreconnect` (M1 and Max) archives and reads App Store Connect, but its role cannot cloud-sign, register bundle IDs or create profiles (403). Distribution therefore signs manually with the "Apple Distribution" certificate in the M1's login keychain and the "Air Posture App Store" profile, and the export must run in the M1's GUI session because SSH cannot unlock the keychain:

```bash
# Max: archive (bump CURRENT_PROJECT_VERSION in project.yml first)
cd apps/air-posture && xcodegen generate
K=~/.appstoreconnect/private_keys/AuthKey_AZ756K8XB6.p8; ISS="$(cat ~/.appstoreconnect/issuer_id)"
xcodebuild archive -project AirPosture.xcodeproj -scheme AirPosture -destination 'generic/platform=iOS' \
  -archivePath /tmp/AirPosture.xcarchive -allowProvisioningUpdates -authenticationKeyPath $K -authenticationKeyID AZ756K8XB6 -authenticationKeyIssuerID "$ISS"
# Copy AirPosture.xcarchive, tools/ExportOptions-manual.plist (as ExportOptions.plist) and
# ../../tools/export-in-gui-session.sh to a dir on the M1, then on the M1:
launchctl submit -l com.user.airposture-export -- <dir>/export-in-gui-session.sh <dir>   # writes <dir>/done and export.log
```

`tools/asc.py` is a small App Store Connect API client on the same key (builds, beta groups, testers, profile download). `tools/brave-js.sh` and `tools/brave-page-js.sh` drive a signed-in Brave over Apple Events for the web-only steps (Brave: View > Developer > Allow JavaScript from Apple Events).
