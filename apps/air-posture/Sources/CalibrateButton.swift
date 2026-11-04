import SwiftUI

/// Recalibrate with visible feedback: "Hold still" with progress, then "Upright set at X°".
struct CalibrateButton: View {
    @ObservedObject var tracker: PostureTracker
    @State private var justSet = false

    var body: some View {
        Button {
            guard tracker.calibrationProgress == nil else { return }
            justSet = false
            tracker.startCalibration()
        } label: {
            HStack(spacing: 10) {
                if let p = tracker.calibrationProgress {
                    ProgressView(value: p).frame(width: 60)
                    Text("Hold still, sitting tall…")
                } else if justSet, let b = tracker.baselinePitch {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Upright set at \(Int(b.rounded()))°").monospacedDigit()
                } else {
                    Image(systemName: "scope")
                    Text("Recalibrate (sit tall first)")
                }
            }
        }
        .disabled(!tracker.running)
        .onChange(of: tracker.calibratedAt) { _, _ in
            guard tracker.calibrationProgress == nil else { return }
            justSet = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                justSet = false
            }
        }
    }
}
