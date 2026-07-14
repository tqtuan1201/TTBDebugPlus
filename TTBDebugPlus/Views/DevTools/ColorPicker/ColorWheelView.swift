//
//  ColorWheelView.swift
//  TTBDebugPlus
//
//  HSB radial color wheel (content gradient — not design chrome).
//

import SwiftUI

struct ColorWheelView: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    var brightness: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2

            ZStack {
                Canvas { context, canvasSize in
                    let steps = 72
                    for i in 0..<steps {
                        let start = Angle.degrees(Double(i) / Double(steps) * 360)
                        let end = Angle.degrees(Double(i + 1) / Double(steps) * 360)
                        var path = Path()
                        path.move(to: center)
                        path.addArc(
                            center: center,
                            radius: radius,
                            startAngle: start - .degrees(90),
                            endAngle: end - .degrees(90),
                            clockwise: false
                        )
                        path.closeSubpath()
                        let h = Double(i) / Double(steps)
                        let color = Color(
                            hue: h,
                            saturation: 1,
                            brightness: max(0.15, brightness)
                        )
                        context.fill(path, with: .color(color))
                    }

                    // Desaturate toward center
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .radialGradient(
                            Gradient(colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0)
                            ]),
                            center: center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.ttBorder.opacity(0.5), lineWidth: 1))

                // Selection knob
                Circle()
                    .fill(Color(
                        hue: hue,
                        saturation: saturation,
                        brightness: max(0.2, brightness)
                    ))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .position(knobPosition(center: center, radius: radius * 0.92))
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateHS(from: value.location, center: center, radius: radius)
                    }
            )
            .accessibilityLabel("Color wheel")
            .accessibilityHint("Drag to change hue and saturation")
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func knobPosition(center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = hue * 2 * .pi - .pi / 2
        let r = CGFloat(saturation) * radius
        return CGPoint(
            x: center.x + cos(angle) * r,
            y: center.y + sin(angle) * r
        )
    }

    private func updateHS(from point: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        let sat = min(1, max(0, Double(dist / max(radius, 1))))
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        let h = angle / (2 * .pi)
        hue = h
        saturation = sat
    }
}
