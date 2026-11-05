import SwiftUI

/// Starts calibration: look straight ahead and keep still until the chime. That direction is 0°.
struct CalibrateButton: View {
    @ObservedObject var tracker: PostureTracker
    var title = "Recalibrate"
    @State private var justSet = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                guard tracker.calibrationProgress == nil else { return }
                justSet = false
                tracker.startCalibration()
            } label: {
                HStack(spacing: 10) {
                    if let p = tracker.calibrationProgress {
                        ProgressView(value: p).frame(width: 60)
                        Text(p > 0 ? "Hold still…" : "Look straight ahead")
                    } else if justSet {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Set: straight ahead is 0°")
                    } else {
                        Image(systemName: "scope")
                        Text(title)
                    }
                }
            }
            if let w = tracker.calibrationWarning, tracker.calibrationProgress == nil {
                Label(w, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onChange(of: tracker.calibratedAt) { _, _ in
            justSet = true
            Task {
                try? await Task.sleep(for: .seconds(4))
                justSet = false
            }
        }
    }
}
