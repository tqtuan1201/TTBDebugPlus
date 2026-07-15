//
//  AnnotationRenderer.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Shared annotation rendering utilities — eliminates duplicate code across
//  DeviceView, AnnotationEditorView, and ScreenCaptureViewModel
//

import SwiftUI

// MARK: - Path Smoothing (Shared)
enum PathSmoothing {
    /// Creates a Bezier-smoothed Path from freehand points.
    /// Used by all annotation renderers (Canvas + CGContext).
    static func smoothedPath(from points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        
        path.move(to: points[0])
        
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
            path.addQuadCurve(to: mid, control: prev)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        
        return path
    }
    
    /// Applies Bezier smoothing to a CGContext path (used in image export).
    static func addSmoothedPath(to context: CGContext, from points: [CGPoint]) {
        guard points.count >= 2 else { return }
        
        context.move(to: points[0])
        
        if points.count == 2 {
            context.addLine(to: points[1])
            return
        }
        
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
            context.addQuadCurve(to: mid, control: prev)
        }
        context.addLine(to: points[points.count - 1])
    }
}

// MARK: - Arrow Geometry
enum ArrowGeometry {
    struct ArrowHead {
        let p1: CGPoint
        let p2: CGPoint
        let tip: CGPoint
    }
    
    /// Compute arrow head points for a line from `start` to `end`
    static func arrowHead(start: CGPoint, end: CGPoint, lineWidth: CGFloat, headLengthMultiplier: CGFloat = 4.0) -> ArrowHead {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLen: CGFloat = max(12, lineWidth * headLengthMultiplier)
        let headAngle: CGFloat = .pi / 6
        
        let p1 = CGPoint(
            x: end.x - headLen * cos(angle - headAngle),
            y: end.y - headLen * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLen * cos(angle + headAngle),
            y: end.y - headLen * sin(angle + headAngle)
        )
        return ArrowHead(p1: p1, p2: p2, tip: end)
    }
}

// MARK: - Shared Canvas Renderer
/// Single source of truth for drawing an annotation into a SwiftUI `GraphicsContext`.
/// Used both by the live editor canvas AND by image export (via ImageRenderer),
/// so what you see in the editor is exactly what gets exported — no Y-flip drift.
enum AnnotationCanvasRenderer {
    static func draw(_ annotation: AnnotationItem, in context: inout GraphicsContext, size: CGSize) {
        let shading: GraphicsContext.Shading = .color(annotation.color)

        switch annotation.tool {
        case .pen:
            if annotation.points.count >= 2 {
                let path = PathSmoothing.smoothedPath(from: annotation.points)
                context.stroke(path, with: shading, style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round))
            }

        case .marker:
            if annotation.points.count >= 2 {
                let path = PathSmoothing.smoothedPath(from: annotation.points)
                context.stroke(path, with: .color(annotation.color.opacity(0.4)),
                              style: StrokeStyle(lineWidth: annotation.lineWidth * 5, lineCap: .round, lineJoin: .round))
            }

        case .highlight:
            if annotation.points.count >= 2 {
                let path = PathSmoothing.smoothedPath(from: annotation.points)
                context.stroke(path, with: .color(annotation.color.opacity(0.35)),
                              style: StrokeStyle(lineWidth: annotation.lineWidth * 4, lineCap: .round, lineJoin: .round))
            }

        case .arrow:
            if annotation.points.count >= 2,
               let start = annotation.points.first, let end = annotation.points.last {
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: shading, style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round))
                let head = ArrowGeometry.arrowHead(start: start, end: end, lineWidth: annotation.lineWidth)
                var arrow = Path()
                arrow.move(to: head.p1)
                arrow.addLine(to: head.tip)
                arrow.addLine(to: head.p2)
                arrow.closeSubpath()
                context.fill(arrow, with: shading)
            }

        case .line:
            if annotation.points.count >= 2,
               let start = annotation.points.first, let end = annotation.points.last {
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: shading, style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round))
            }

        case .rectangle:
            if let rect = annotation.boundingRect {
                let path = Path(roundedRect: rect, cornerRadius: 3)
                if annotation.isFilled {
                    context.fill(path, with: .color(annotation.color.opacity(0.3)))
                }
                context.stroke(path, with: shading, lineWidth: annotation.lineWidth)
            }

        case .ellipse:
            if let rect = annotation.boundingRect {
                let path = Path(ellipseIn: rect)
                if annotation.isFilled {
                    context.fill(path, with: .color(annotation.color.opacity(0.3)))
                }
                context.stroke(path, with: shading, lineWidth: annotation.lineWidth)
            }

        case .text:
            if let pos = annotation.points.first {
                let textSize = DesignSystemConfig.shared.annotationFontSize(
                    lineWidth: annotation.lineWidth,
                    multiplier: 4,
                    minimumBase: 14
                )
                let text = Text(annotation.text)
                    .font(.system(size: textSize, weight: .medium))
                    .foregroundColor(annotation.color)
                context.draw(context.resolve(text), at: pos, anchor: .topLeading)
            }

        case .stepCounter:
            if let pos = annotation.points.first {
                let r: CGFloat = DesignSystemConfig.shared.annotationFontSize(
                    lineWidth: annotation.lineWidth,
                    multiplier: 3,
                    minimumBase: 14
                )
                let circleRect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: circleRect), with: shading)
                context.stroke(Path(ellipseIn: circleRect), with: .color(.white.opacity(0.8)), lineWidth: 2)
                let numText = Text("\(annotation.stepNumber)")
                    .font(.system(size: r * 1.1, weight: .bold))
                    .foregroundColor(.ttTextPrimary)
                context.draw(context.resolve(numText), at: pos, anchor: .center)
            }

        case .blur:
            if let rect = annotation.boundingRect {
                let cellSize: CGFloat = 10
                for row in stride(from: rect.minY, to: rect.maxY, by: cellSize) {
                    for col in stride(from: rect.minX, to: rect.maxX, by: cellSize) {
                        let cellRect = CGRect(x: col, y: row, width: cellSize, height: cellSize).intersection(rect)
                        let hash = Int(abs(sin(col * 12.9898 + row * 78.233) * 43758.5453).truncatingRemainder(dividingBy: 1.0) * 100)
                        let gray = Double(hash) / 100.0 * 0.4 + 0.3
                        context.fill(Path(cellRect), with: .color(.gray.opacity(gray)))
                    }
                }
                context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(.gray.opacity(0.5)), lineWidth: 1)
            }

        case .spotlight:
            if let spotRect = annotation.boundingRect {
                let fullRect = CGRect(origin: .zero, size: size)
                var maskPath = Path(fullRect)
                maskPath.addRoundedRect(in: spotRect, cornerSize: CGSize(width: 6, height: 6))
                context.fill(maskPath, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                context.stroke(Path(roundedRect: spotRect, cornerRadius: 6), with: .color(annotation.color), lineWidth: 2.5)
            }

        case .eraser:
            break
        }
    }
}

// MARK: - Two-Point Rect Helper
extension AnnotationItem {
    /// Computes a normalized CGRect from the first and last annotation points.
    /// Returns nil if fewer than 2 points.
    var boundingRect: CGRect? {
        guard let s = points.first, let e = points.last, points.count >= 2 else { return nil }
        return CGRect(
            x: min(s.x, e.x), y: min(s.y, e.y),
            width: abs(e.x - s.x), height: abs(e.y - s.y)
        )
    }
}
