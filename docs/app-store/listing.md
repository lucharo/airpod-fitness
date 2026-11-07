# App Store listing, version 1.0.1

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

Simple, minimal sound feedback to help keep good posture when walking or looking at a screen.

## Description

Works with AirPods Pro, AirPods 3 and 4, AirPods Max and Beats Fit Pro.

Simple, minimal sound feedback to help keep good posture when walking or looking at a screen.

Open source: https://github.com/lucharo/airpod-fitness

## Screenshots

`screenshots/` holds the 1320 × 2868 set uploaded for iPhone. They are the real app on the iPhone 17 Pro Max simulator with the built-in demo motion, because the simulator has no headphone motion. The 22° reading matches the desk posture in `data/recordings` (21.8° and 22.0°). Reproduce with `-demo -demoDrop 22 -skipOnboarding`.
