import CoreMotion
import Foundation

/// One head-motion sample, from the AirPods or synthesised in demo mode.
struct MotionSample {
    var tSensor: TimeInterval
    var qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0
    var pitch = 0.0, roll = 0.0, yaw = 0.0          // degrees
    var gravX = 0.0, gravY = 0.0, gravZ = -1.0       // g
    var accX = 0.0, accY = 0.0, accZ = 0.0           // user acceleration, g
    var rotX = 0.0, rotY = 0.0, rotZ = 0.0           // rad/s
    var sensor = "default"

    var rotationRate: Double { (rotX * rotX + rotY * rotY + rotZ * rotZ).squareRoot() }
    var acceleration: Double { (accX * accX + accY * accY + accZ * accZ).squareRoot() }

    init(tSensor: TimeInterval) { self.tSensor = tSensor }

    init(_ m: CMDeviceMotion) {
        let deg = 180 / Double.pi
        let q = m.attitude.quaternion
        tSensor = m.timestamp
        qx = q.x; qy = q.y; qz = q.z; qw = q.w
        pitch = m.attitude.pitch * deg; roll = m.attitude.roll * deg; yaw = m.attitude.yaw * deg
        gravX = m.gravity.x; gravY = m.gravity.y; gravZ = m.gravity.z
        accX = m.userAcceleration.x; accY = m.userAcceleration.y; accZ = m.userAcceleration.z
        rotX = m.rotationRate.x; rotY = m.rotationRate.y; rotZ = m.rotationRate.z
        switch m.sensorLocation {
        case .headphoneLeft: sensor = "left"
        case .headphoneRight: sensor = "right"
        default: sensor = "default"
        }
    }
}
