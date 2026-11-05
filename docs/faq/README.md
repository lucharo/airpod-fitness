# FAQ

## Can AirPods alone tell whether my posture is bad?

Partly. `CMHeadphoneMotionManager` gives one fused head orientation (pitch, roll, yaw, rotation rate, acceleration) at about 50 Hz from AirPods Pro, AirPods 3 and 4, AirPods Max and Beats Fit Pro. It sees the head dropping or tilting clearly: in the first recording (`data/recordings/air-posture-positions-2026-11-04T15-37-50Z.*`), looking at the lap was about 40 to 50° down, the desk about 22° and leaning in about 20°. It does not see position, so chin forward (eyes level) and slouching with eyes level barely register (−4° and 0° on average). (2026-11-04)

## Why does slouching while looking straight ahead still read 0°?

The app measures where your head points, not where your back is. Slouching with your eyes still level leaves head pitch almost unchanged. Catching that needs a second sensor on the trunk: the recorder's pocket mode logs the iPhone's own motion for that, and a chest strap such as a Polar H10 is another option. Early builds made it worse by calibrating while you looked at the phone (a −28° reference); since build 8 calibration asks you to look straight ahead. (2026-11-05)

## How is the angle calculated, and how do I know 12° is right?

It is AirPods pitch minus the pitch saved at calibration ("look straight ahead and keep still"), so 0° is straight ahead and positive is down. Absolute pitch depends on how the bud sits in your ear, which is why only the difference is used. A rough check: after calibrating, look at the floor about a metre in front of your feet; the reading should be roughly 40 to 50°. The nudge angle is adjustable on the main screen (drag the dashed line or use − and +). (2026-11-05)

## Could the Apple Watch and iPhone triangulate the AirPods' position?

No. Third-party apps cannot run code on AirPods, and iOS exposes no Bluetooth signal strength for them (which is metre-level anyway). Ultra-wideband ranges iPhone to Watch only, with distance but no direction on watchOS, and the AirPods earbuds have no UWB chip. A wrist also says nothing about the spine. Apple forum reports say headphone motion is unavailable on watchOS. (2026-11-03)

## Is Posture Pal open source, and when did it come out?

No evidence that it is open source: it is a commercial app by Jordi Bruin's Good Snooze, launched around March 2022, at https://apps.apple.com/us/app/id1590316152 . It alerts at 10, 20 or 35° of neck tilt. (2026-11-03)

## Does tracking keep running in the background?

Yes (confirmed on device, 2026-11-05). A silent audio engine keeps the app alive. Apps that use the microphone (dictation, calls) interrupt that audio; build 10 restarts audio and motion afterwards, and build 11 shows a "Sound is off" banner with a one-tap restore. Both are untested on device. Note that a silent audio engine may not pass App Store review.

## What happens when I take an AirPod out?

By default nudges pause and resume when it goes back in, and the app offers to recalibrate. iOS only reports which AirPod the motion comes from (Settings → Measuring from), not whether both are in, so only removing the measuring AirPod pauses. Turn "Pause when an AirPod comes out" off to keep tracking with one AirPod. When both disconnect, nudges pause and sound never plays through the phone speaker (build 14). (2026-11-05)

## How do I ship a build or read TestFlight feedback?

`tools/ship-testflight.sh` from the repo root: it bumps the build, archives with the App Store Connect API key, exports and uploads on the M1 and waits for processing. Feedback: `uv run tools/asc.py GET "/v1/apps/6830647347/betaFeedbackScreenshotSubmissions"`. See the README's TestFlight section for why signing happens on the M1. (2026-11-05)
