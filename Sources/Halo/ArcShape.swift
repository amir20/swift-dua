import SwiftUI

/// A donut wedge between two radii and two angles (radians, measured clockwise
/// from 12 o'clock at -π/2), reproducing the design's `arc(r0,r1,a0,a1)`.
/// `endAngle` and `outerRadius` are animatable so slices can sweep in and lift
/// on hover.
struct ArcShape: Shape {
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var startAngle: Double
    var endAngle: Double
    /// Center in the shape's own coordinate space. The design centers at (230,230).
    var center = CGPoint(x: 230, y: 230)

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(endAngle, Double(outerRadius)) }
        set {
            endAngle = newValue.first
            outerRadius = CGFloat(newValue.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard endAngle > startAngle + 0.0002 else { return p }
        let a0 = Angle.radians(startAngle)
        let a1 = Angle.radians(endAngle)
        p.addArc(
            center: center, radius: outerRadius, startAngle: a0, endAngle: a1, clockwise: false)
        p.addLine(to: point(innerRadius, endAngle))
        p.addArc(center: center, radius: innerRadius, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        return p
    }

    private func point(_ r: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
    }
}
