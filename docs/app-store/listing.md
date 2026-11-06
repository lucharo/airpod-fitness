# App Store listing, version 1.0

What App Store Connect holds for app 6830647347. The folder, bundle ID (`lucharo.airposture`) and Xcode project keep the Air Posture name; users never see them. The API key cannot write the listing, so changes go through the App Store Connect website.

| Field | Value |
| --- | --- |
| Name | Heads Up: posture nudges |
| Home screen name | Heads Up! |
| Subtitle | Simple feedback with AirPods |
| Category | Health & Fitness |
| Price | Free, all 175 territories |
| Age rating | 4+ (health or wellness topics: yes; everything else: no or none) |
| Regulated medical device | No |
| App privacy | Data Not Collected |
| Release | Manual |
| Privacy policy | https://lucharo.github.io/heads-up/privacy/ |
| Support | https://lucharo.github.io/heads-up/support/ |
| Public TestFlight link | https://testflight.apple.com/join/CkYVdbWw |

The privacy and support pages live in `lucharo/lucharo.github.io` under `heads-up/`.

`AirPosture` was not used because "AirPosture: Sit Straight" by Relja Bulajic is live with the same idea. `Heads Up!` and `Heads Up` are taken by Warner Bros' game, and App Store Connect refuses them in any capitalisation.

## Keywords

neck,slouch,head,tilt,desk,sitting,ergonomics,reminder,tech neck,headphones,motion,upright

## Promotional text

A soft tone in your AirPods when your head drops forward. Lift your head and it stops.

## Description

Heads Up! notices when your head drops forward while you sit, and tells you with a soft tone in your AirPods. The further it drops, the stronger the tone. Lift your head and it stops.

It works with AirPods Pro, AirPods 3 and 4, AirPods Max and Beats Fit Pro, using the motion sensors already inside them. There's nothing else to wear or charge.

HOW IT WORKS
1. Put your AirPods in, look straight ahead and keep still to set your zero.
2. Choose how far your head can drop before you get a nudge. It starts at 12°.
3. Carry on with your day. Nudges keep working while you use other apps, and they mix with your music.

You also get a soft chime if you've kept still for a while. It's set to 30 minutes and you can change it.

WHAT IT MEASURES
Heads Up! measures your head, not your back. Leaning your whole body forward counts as your head dropping, and slouching with your eyes level doesn't show.

PRIVATE
No account, no ads, no tracking. Motion readings stay on your iPhone.

Heads Up! is for everyday awareness. It isn't a medical device and doesn't diagnose or treat anything. If you have neck or back pain, talk to a doctor.

AirPods is a trademark of Apple Inc. Heads Up! is not affiliated with or endorsed by Apple.

## Screenshots

`screenshots/` holds the 1320 × 2868 set uploaded for iPhone. They are the real app on the iPhone 17 Pro Max simulator with the built-in demo motion, because the simulator has no headphone motion. The 22° reading matches the desk posture in `data/recordings` (21.8° and 22.0°). Reproduce with `-demo -demoDrop 22 -skipOnboarding`.

