# AirPod Fitness

Apps that use AirPods head motion as a body sensor.

| App | Status | Idea |
| --- | --- | --- |
| [Air Posture](apps/air-posture) | spike | Notice when your head drops forward and give graded audio feedback; remind you to move after long stillness. |
| RepSense | idea | Count reps (push-ups, squats, pull-ups) from head motion, optionally fused with Apple Watch. |

Design notes: [docs/design.md](docs/design.md). Earlier conversations that led here: [docs/prior-conversations](docs/prior-conversations).

## Run Air Posture

Needs a real iPhone and motion-capable AirPods (Pro, 3rd gen or later, Max, Beats Fit Pro); the simulator has no headphone motion.

```bash
cd apps/air-posture
xcodegen generate
open AirPosture.xcodeproj   # pick your iPhone, Run
```

Spike test: Start, sit tall, Calibrate, lock the phone for 10 minutes while slouching now and then, then reopen. "Samples in background" and "Longest gap in background" answer whether tracking survives in the background; Export log gives the CSV.

## TestFlight

Signing uses the App Store Connect API key in `~/.appstoreconnect` (M1 and Max); no Xcode login needed.

```bash
cd apps/air-posture && xcodegen generate
K=~/.appstoreconnect/private_keys/AuthKey_AZ756K8XB6.p8; ISS="$(cat ~/.appstoreconnect/issuer_id)"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath $K -authenticationKeyID AZ756K8XB6 -authenticationKeyIssuerID "$ISS")
xcodebuild archive -project AirPosture.xcodeproj -scheme AirPosture -destination 'generic/platform=iOS' -archivePath /tmp/AirPosture.xcarchive "${AUTH[@]}"
xcodebuild -exportArchive -archivePath /tmp/AirPosture.xcarchive -exportOptionsPlist tools/ExportOptions.plist -exportPath /tmp/AirPosture-export "${AUTH[@]}"
```

Bump `CURRENT_PROJECT_VERSION` in `project.yml` before each upload. `tools/asc.py` is a tiny App Store Connect API client using the same key. The key's role cannot register bundle IDs (403), so the first upload needs the App ID and the App Store Connect app record created in a browser signed in to the account.
