import SwiftUI

/// Head drop drawn as the angle itself: a line from the eye tilting down from a dashed
/// straight-ahead line (0°), with the nudge zone beyond the dashed nudge line.
/// Drag anywhere on the drawing to move the nudge line.

private let scaleMax = 40.0   // degrees shown, bottom of the scale

struct AngleGauge: View {
    @ObservedObject var tracker: PostureTracker

    var body: some View {
        let drop = clamp(tracker.drop)
        VStack(spacing: 16) {
            Canvas { ctx, size in
                let eye = CGPoint(x: 40, y: 40)
                let len = size.width - 70
                let ray = { (d: Double) -> CGPoint in
                    let a = d * .pi / 180
                    return CGPoint(x: eye.x + len * cos(a), y: eye.y + len * sin(a))
                }
                // nudge zone: the wedge beyond the threshold, lightly shaded, edge dashed
                var zone = Path()
                zone.move(to: eye)
                zone.addArc(center: eye, radius: len, startAngle: .degrees(tracker.thresholdDegrees), endAngle: .degrees(scaleMax), clockwise: false)
                zone.closeSubpath()
                ctx.fill(zone, with: .color(.secondary.opacity(0.12)))
                var edge = Path(); edge.move(to: eye); edge.addLine(to: ray(tracker.thresholdDegrees))
                ctx.stroke(edge, with: .color(.primary), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                // straight ahead
                var ahead = Path(); ahead.move(to: eye); ahead.addLine(to: ray(0))
                ctx.stroke(ahead, with: .color(.secondary), style: StrokeStyle(lineWidth: 2, dash: [2, 5]))
                ctx.draw(Text("straight ahead 0°").font(.caption).foregroundStyle(.secondary), at: CGPoint(x: ray(0).x, y: ray(0).y - 12), anchor: .trailing)
                // trail: the last few seconds as fading lines
                let h = tracker.dropHistory.suffix(25)
                for (i, d) in h.enumerated() where i % 3 == 0 {
                    var r = Path(); r.move(to: eye); r.addLine(to: ray(clamp(d)))
                    ctx.stroke(r, with: .color(.primary.opacity(0.06 + 0.25 * Double(i) / 25)), lineWidth: 2)
                }
                // current head direction
                var now = Path(); now.move(to: eye); now.addLine(to: ray(drop))
                ctx.stroke(now, with: .color(.primary), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: ray(drop).x - 8, y: ray(drop).y - 8, width: 16, height: 16)), with: .color(.primary))
                ctx.fill(Path(ellipseIn: CGRect(x: eye.x - 9, y: eye.y - 9, width: 18, height: 18)), with: .color(.primary))
            }
            .frame(height: 250)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { g in
                // angle from the eye (40, 40) to the finger sets the nudge
                let dx = max(g.location.x - 52, 1), dy = g.location.y - 40
                let deg = atan2(dy, dx) * 180 / .pi
                tracker.thresholdDegrees = min(max(deg.rounded(), PostureTracker.nudgeRange.lowerBound), PostureTracker.nudgeRange.upperBound)
            })
            .accessibilityElement()
            .accessibilityLabel("Head \(Int(drop.rounded())) degrees below straight ahead, nudge at \(Int(tracker.thresholdDegrees)) degrees")
            .accessibilityAdjustableAction { dir in
                tracker.thresholdDegrees += dir == .increment ? 1 : -1
                tracker.thresholdDegrees = min(max(tracker.thresholdDegrees, PostureTracker.nudgeRange.lowerBound), PostureTracker.nudgeRange.upperBound)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(drop.rounded()))°").font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("below straight ahead").font(.subheadline).foregroundStyle(.secondary)
            }
            StatusLine(tracker: tracker).font(.title2.weight(.semibold))
            Stepper(value: $tracker.thresholdDegrees, in: PostureTracker.nudgeRange, step: 1) {
                Text("Nudge at \(Int(tracker.thresholdDegrees))°").monospacedDigit()
            }
            .frame(maxWidth: 260)
            Text("The dashed line is the nudge: drag it, or use − and +").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private func clamp(_ d: Double) -> Double { min(max(d, 0), scaleMax) }
