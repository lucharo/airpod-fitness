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
