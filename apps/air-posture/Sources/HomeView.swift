import SwiftUI

/// Main screen: one status, one button, settings behind a gear.
/// Three layouts (A gauge, B big word, C plumb line) are switchable in Settings → Prototype.
struct HomeView: View {
    @ObservedObject var tracker: PostureTracker
    @AppStorage("homeVariant") private var variant = Self.launchVariant
    @State private var showSettings = false

    static var launchVariant: String {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: "-variant").map { args[$0 + 1] } ?? "A"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                switch variant {
                case "B": BigWordStatus(tracker: tracker)
                case "C": PlumbStatus(tracker: tracker)
                default: GaugeStatus(tracker: tracker)
                }
                Spacer(minLength: 0)
                if !tracker.connected && tracker.running {
                    Label("AirPods not connected", systemImage: "airpods")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button {
                    tracker.running ? tracker.stop() : tracker.start()
                } label: {
                    Label(tracker.running ? "Pause" : "Resume",
                          systemImage: tracker.running ? "pause.fill" : "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("Air Posture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(tracker: tracker, variant: $variant)
            }
        }
    }
}

/// Shared wording; colour never carries the meaning on its own (icon + words).
struct StatusLine: View {
    @ObservedObject var tracker: PostureTracker
    var body: some View {
        if !tracker.running {
            Label("Paused", systemImage: "pause.circle")
        } else if tracker.isUpright {
            Label("Upright", systemImage: "checkmark.circle.fill")
        } else {
            Label("Head dropping", systemImage: "arrow.down.circle.fill")
        }
    }
}

// MARK: A — gauge

struct GaugeStatus: View {
    @ObservedObject var tracker: PostureTracker
    private let maxDrop = 30.0

    var body: some View {
        let drop = min(max(tracker.drop, 0), maxDrop)
        VStack(spacing: 18) {
            ZStack {
                Arc(from: 0, to: 1).stroke(Color.secondary.opacity(0.2), style: .init(lineWidth: 18, lineCap: .round))
                Arc(from: 0, to: drop / maxDrop)
                    .stroke(tracker.isUpright ? Color.primary : Color.orange, style: .init(lineWidth: 18, lineCap: .round))
                Tick(fraction: tracker.thresholdDegrees / maxDrop)
                    .stroke(Color.primary, style: .init(lineWidth: 3, dash: [4, 3]))
                VStack(spacing: 2) {
                    Text("\(Int(drop.rounded()))°").font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("forward").font(.subheadline).foregroundStyle(.secondary)
                }
                .offset(y: 30)
            }
            .frame(width: 280, height: 170)
            StatusLine(tracker: tracker).font(.title2.weight(.semibold))
            Text("Nudge starts at \(Int(tracker.thresholdDegrees))° (dashed mark)")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct Arc: Shape {
    var from: Double, to: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.maxY)
        let radius = min(r.width / 2, r.height) - 10
        p.addArc(center: c, radius: radius, startAngle: .degrees(180 + 180 * from),
                 endAngle: .degrees(180 + 180 * to), clockwise: false)
        return p
    }
}

struct Tick: Shape {
    var fraction: Double
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.maxY)
        let radius = min(r.width / 2, r.height) - 10
        let a = Angle.degrees(180 + 180 * min(fraction, 1)).radians
        var p = Path()
        p.move(to: CGPoint(x: c.x + (radius - 22) * cos(a), y: c.y + (radius - 22) * sin(a)))
        p.addLine(to: CGPoint(x: c.x + (radius + 22) * cos(a), y: c.y + (radius + 22) * sin(a)))
        return p
    }
}

// MARK: B — big word

struct BigWordStatus: View {
    @ObservedObject var tracker: PostureTracker
    var body: some View {
        let drop = max(tracker.drop, 0)
        VStack(alignment: .leading, spacing: 16) {
            StatusLine(tracker: tracker)
                .font(.system(size: 44, weight: .bold))
                .labelStyle(.titleOnly)
            Text(tracker.isUpright
                 ? "Head \(Int(drop.rounded()))° from your upright position."
                 : "Head \(Int(drop.rounded()))° forward. Lift your chin and sit back.")
                .font(.title3).foregroundStyle(.secondary)
            GeometryReader { g in
                let w = g.size.width
                let frac = min(drop / 30, 1)
                let t = min(tracker.thresholdDegrees / 30, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(tracker.isUpright ? Color.primary : Color.orange).frame(width: max(12, w * frac))
                    Rectangle().fill(Color.primary).frame(width: 3, height: 30).offset(x: w * t - 1.5)
                }
            }
            .frame(height: 14)
            HStack {
                Text("0°"); Spacer(); Text("nudge \(Int(tracker.thresholdDegrees))°"); Spacer(); Text("30°")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: C — plumb line

struct PlumbStatus: View {
    @ObservedObject var tracker: PostureTracker
    var body: some View {
        let drop = min(max(tracker.drop, 0), 40)
        VStack(spacing: 18) {
            ZStack(alignment: .top) {
                Path { p in p.move(to: CGPoint(x: 120, y: 0)); p.addLine(to: CGPoint(x: 120, y: 260)) }
                    .stroke(Color.secondary.opacity(0.5), style: .init(lineWidth: 2, dash: [6, 6]))
                VStack(spacing: 0) {
                    Rectangle().fill(Color.primary).frame(width: 2, height: 190)
                    Capsule().fill(Color.primary).frame(width: 34, height: 58)
                        .overlay(Circle().fill(Color(uiColor: .systemBackground)).frame(width: 10).offset(y: -12))
                }
                .rotationEffect(.degrees(drop), anchor: .top)
                .animation(.easeOut(duration: 0.3), value: drop)
            }
            .frame(width: 240, height: 260)
            StatusLine(tracker: tracker).font(.title2.weight(.semibold))
            Text("\(Int(drop.rounded()))° off the line · nudge at \(Int(tracker.thresholdDegrees))°")
                .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
