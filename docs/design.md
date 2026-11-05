# Design notes (2026-11-03)

## What AirPods can sense

`CMHeadphoneMotionManager` gives one fused head pose at about 25 Hz: attitude (pitch, roll, yaw), rotation rate, gravity, user acceleration. No per-bud position. Supported: AirPods Pro (all), AirPods 3 and 4, AirPods Max, Beats Fit Pro. AirPods 1 and 2 have no motion sensor.

- Senses well: head dropping forward or down (pitch), tilting (roll), turning (yaw), stillness.
- Senses badly: forward head posture with level gaze, and back slouch. Both are translations, which an IMU cannot track over seconds. Posture Pal reviewers report the same blind spot.

## Why not triangulate with the Watch and iPhone

- Third-party code cannot run on AirPods, and iOS exposes no Bluetooth signal strength for them; signal strength is metre-level anyway.
- Ultra-wideband (Nearby Interaction) ranges iPhone to Watch, but on watchOS it reports distance only, AirPods earbuds have no UWB, and the wrist says nothing about the spine.
- Apple forum reports say headphone motion is unavailable on watchOS (`isDeviceMotionAvailable` false). Verify before RepSense plans a Watch-only app.

## The ambitious version that can work

1. Camera as ground truth: at the desk, the Mac or iPhone camera (Vision body pose) measures real forward-head and slouch angles.
2. Personal calibration: learn how the AirPods signal moves between good and bad posture as measured by the camera.
3. Away from the camera, AirPods alone apply that calibration.
4. Watch: wrist haptics and the movement reminder, not posture.

## Spike questions (apps/air-posture), answered 2026-11-05

1. Background: yes, tracking continues with the phone locked (confirmed on device). Microphone use interrupts the audio; recovery is in build 10 and later.
2. and 3. A calibrated pitch drop works as the trigger; the nudge angle is now user-adjustable. Slouching needs a trunk sensor (issue #2).

The original questions:

1. Does headphone motion keep streaming with the phone locked, given an active audio session? Read from "Longest gap in background" and the CSV.
2. Is pitch drop past a calibrated baseline a usable trigger, and what threshold feels right?
3. Does graded tone feedback (silent below threshold, louder and higher past it) help or annoy?

Note: keeping the app alive with a silent audio engine is fine for a spike but may not pass App Store review; Posture Pal's approach is worth checking before shipping.

## Existing apps

- Posture Pal (Good Snooze, Jordi Bruin, since about March 2022): https://apps.apple.com/us/app/id1590316152 . Closed source; alerts at 10, 20 or 35 degrees of neck tilt; iOS and Mac.
- Posture Reminder: Upright: https://apps.apple.com/app/id6749187831
