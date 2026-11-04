import SwiftUI

/// Main screen: a gauge, one status, one button, settings behind a gear.
struct HomeView: View {
    @ObservedObject var tracker: PostureTracker
    @State private var showSettings = false
    @State private var showRecorder = ProcessInfo.processInfo.arguments.contains("-recorder")

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                GaugeStatus(tracker: tracker)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { showRecorder = true } label: { Label("Record", systemImage: "record.circle") }
                        .labelStyle(.titleAndIcon)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(tracker: tracker)
            }
            .fullScreenCover(isPresented: $showRecorder) {
                RecordView(tracker: tracker)
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

// MARK: Gauge

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
