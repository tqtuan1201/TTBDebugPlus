//
//  AnnotationEditorView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-28.
//  Full-screen annotation editor — CleanShot X inspired
//
//  Architecture:
//   - Two-row toolbar: Row1 = tools + actions, Row2 = color/size/zoom
//   - DragGesture on transparent overlay INSIDE the zoom/pan transform
//     so gesture coords match Canvas coords exactly (no conversion needed)
//   - MagnificationGesture + scroll-wheel on outer container for zoom
//   - Option+drag for panning
//

import SwiftUI

struct AnnotationEditorView: View {
    let baseImage: NSImage
    @Binding var annotations: [AnnotationItem]

    // Copy actions wired by the host (DeviceView) — enables in-editor copy buttons.
    var onCopyPlain: (() -> Void)? = nil
    var onCopyWithInfo: (() -> Void)? = nil
    /// Reports the fitted canvas size (display coords) so the host can scale
    /// annotation points to full image resolution on export.
    var onCanvasSizeChange: ((CGSize) -> Void)? = nil

    var onDone: () -> Void
    var onCancel: () -> Void

    @State private var selectedTool: AnnotationTool = .pen
    @State private var selectedColor: Color = .red
    @State private var lineWidth: CGFloat = 3.0
    @State private var currentDragPoints: [CGPoint] = []
    @State private var textInput: String = ""
    @State private var showTextInput: Bool = false
    @State private var textPosition: CGPoint = .zero
    @State private var stepCounter: Int = 0
    @State private var zoomScale: CGFloat = 1.0
    @State private var accumulatedZoom: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var fillShape: Bool = false

    // MARK: - Selection / Edit Mode (Item 3)
    @State private var isSelectMode: Bool = false
    @State private var selectedAnnotationID: UUID? = nil
    @State private var moveStartPoints: [CGPoint]? = nil     // snapshot at drag start (move)
    @State private var resizeHandle: Int? = nil             // index into selected annotation's points
    @State private var editingTextID: UUID? = nil           // text annotation being re-edited

    // Unlimited undo/redo
    @State private var redoStack: [AnnotationItem] = []

    // MARK: - Persistence (Item 2)
    @AppStorage("annEditor.lastToolRaw") private var lastToolRaw: String = AnnotationTool.pen.rawValue
    @AppStorage("annEditor.lastColorHex") private var lastColorHex: String = "#FF3B30"
    @AppStorage("annEditor.lastLineWidth") private var lastLineWidth: Double = 3.0
    @AppStorage("annEditor.customColorsHex") private var customColorsHex: String = ""

    let colorPalette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]

    /// Tools that expose endpoint resize handles when selected (2-point shapes).
    private let resizableShapes: Set<AnnotationTool> = [.arrow, .line, .rectangle, .ellipse, .blur, .spotlight]

    private var customColors: [Color] {
        customColorsHex.split(separator: ",")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .map { Color(hex: $0) }
    }

    private var selectedAnnotation: AnnotationItem? {
        guard let id = selectedAnnotationID else { return nil }
        return annotations.first { $0.id == id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Tools + Close/Done
            toolRow
            
            Divider().background(Color.ttBorder.opacity(0.5))
            
            // Row 2: Color, Size, Zoom
            propertyRow
            
            Divider().background(Color.ttBorder)
            
            // Canvas area
            canvasArea
            
            Divider().background(Color.ttBorder)
            
            // Status bar
            bottomStatusBar
        }
        .background(Color.ttBackground)
        // Hidden keyboard-shortcut layer (disabled while typing text)
        .background {
            if !showTextInput { shortcutLayer }
        }
        // Text input overlay
        .overlay {
            if showTextInput {
                textInputOverlay
            }
        }
        .onAppear {
            stepCounter = annotations.filter { $0.tool == .stepCounter }.count
            // Restore last-used tool / color / width
            if let tool = AnnotationTool(rawValue: lastToolRaw) { selectedTool = tool }
            selectedColor = Color(hex: lastColorHex)
            lineWidth = CGFloat(lastLineWidth)
        }
        .onChange(of: selectedTool) { _, newValue in lastToolRaw = newValue.rawValue }
        .onChange(of: lineWidth) { _, newValue in
            lastLineWidth = Double(newValue)
            applyToSelection { $0.lineWidth = newValue }
        }
        .onChange(of: selectedColor) { _, newValue in
            lastColorHex = newValue.hexRGB
            applyToSelection { $0.color = newValue }
        }
    }

    // MARK: - Keyboard Shortcut Layer
    /// Invisible buttons that bind single-key tool shortcuts (P, A, R, …) plus V = select.
    private var shortcutLayer: some View {
        ZStack {
            Button("") { isSelectMode = true }
                .keyboardShortcut("v", modifiers: [])
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                Button("") { selectTool(tool) }
                    .keyboardShortcut(KeyEquivalent(Character(tool.shortcutHint.lowercased())), modifiers: [])
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func selectTool(_ tool: AnnotationTool) {
        selectedTool = tool
        isSelectMode = false
        selectedAnnotationID = nil
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Row 1: Tool Row
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var toolRow: some View {
        HStack(spacing: TTSpacing.xs) {
            // Close button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(TTFont.labelMedium)
                    .foregroundColor(.ttTextSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.ttSurface)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ttBorder.opacity(0.5), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .keyboardShortcut(.escape, modifiers: [])
            
            Divider().frame(height: 24).padding(.horizontal, TTSpacing.xxxs)

            // Select / move / resize mode
            Button(action: { isSelectMode.toggle(); if !isSelectMode { selectedAnnotationID = nil } }) {
                Image(systemName: "cursorarrow")
                    .font(TTFont.bodyMedium)
                    .foregroundColor(isSelectMode ? .white : .ttTextSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelectMode ? Color.ttPrimary : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Select / Move / Resize (V)")

            Divider().frame(height: 24).padding(.horizontal, TTSpacing.xxxs)

            // All tools — icon only, compact 30×30
            toolButton(.pen)
            toolButton(.marker)
            toolButton(.highlight)
            
            Divider().frame(height: 24).padding(.horizontal, TTSpacing.xxxs)
            
            toolButton(.arrow)
            toolButton(.line)
            toolButton(.rectangle)
            toolButton(.ellipse)
            
            // Fill toggle (only shown for rect/ellipse)
            if selectedTool == .rectangle || selectedTool == .ellipse {
                Button(action: { fillShape.toggle() }) {
                    Image(systemName: fillShape ? "square.fill" : "square")
                        .font(.ttIcon(TTIcon.md))
                        .foregroundColor(fillShape ? .ttPrimary : .ttTextTertiary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(fillShape ? Color.ttPrimary.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help("Fill shape")
            }
            
            Divider().frame(height: 24).padding(.horizontal, TTSpacing.xxxs)
            
            toolButton(.text)
            toolButton(.stepCounter)
            toolButton(.blur)
            toolButton(.spotlight)
            
            Divider().frame(height: 24).padding(.horizontal, TTSpacing.xxxs)
            
            toolButton(.eraser)
            
            Spacer()
            
            // Undo/Redo/Clear
            HStack(spacing: TTSpacing.inlineGapSmall) {
                Button(action: localUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.ttIcon(TTIcon.lg))
                }
                .buttonStyle(.ttGhost)
                .disabled(annotations.isEmpty)
                .keyboardShortcut("z", modifiers: .command)
                
                Button(action: localRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.ttIcon(TTIcon.lg))
                }
                .buttonStyle(.ttGhost)
                .disabled(redoStack.isEmpty)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                
                Button(action: {
                    annotations.removeAll()
                    redoStack.removeAll()
                    stepCounter = 0
                }) {
                    Image(systemName: "trash")
                        .font(.ttIcon(TTIcon.md))
                }
                .buttonStyle(.ttGhost)
                .disabled(annotations.isEmpty)
            }
            
            Divider().frame(height: 24).padding(.horizontal, TTSpacing.xxxs)

            // Copy actions (only when device context is available)
            if onCopyPlain != nil || onCopyWithInfo != nil {
                HStack(spacing: TTSpacing.inlineGapSmall) {
                    if let onCopyPlain {
                        Button(action: onCopyPlain) {
                            Image(systemName: "doc.on.doc")
                                .font(.ttIcon(TTIcon.lg))
                        }
                        .buttonStyle(.ttGhost)
                        .help("Copy image to clipboard")
                    }
                    if let onCopyWithInfo {
                        Button(action: onCopyWithInfo) {
                            HStack(spacing: TTSpacing.xxs) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(TTFont.badge)
                                Text("Copy + Info")
                                    .font(TTFont.labelMedium)
                            }
                        }
                        .buttonStyle(.ttSecondaryCompact)
                        .help("Copy image with a device-info footer — ready for tester/PM")
                    }
                }

                Divider().frame(height: 24).padding(.horizontal, TTSpacing.xxxs)
            }

            // Done button
            Button(action: onDone) {
                HStack(spacing: TTSpacing.xxs) {
                    Image(systemName: "checkmark")
                        .font(TTFont.badge)
                    Text("Done")
                        .font(TTFont.labelMedium)
                }
            }
            .buttonStyle(.ttPrimaryCompact)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, TTSpacing.inputPaddingH)
        .padding(.vertical, TTSpacing.xs)
        .background(Color.ttSurface.opacity(0.95))
    }
    
    // MARK: - Single Tool Button (icon only, 30×30)
    private func toolButton(_ tool: AnnotationTool) -> some View {
        let isSelected = selectedTool == tool && !isSelectMode
        return Button(action: { selectTool(tool) }) {
            Image(systemName: tool.icon)
                .font(TTFont.bodyMedium)
                .foregroundColor(isSelected ? .white : .ttTextSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.ttPrimary : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help("\(tool.rawValue) (\(tool.shortcutHint))")
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Row 2: Properties
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var propertyRow: some View {
        HStack(spacing: TTSpacing.sm) {
            // Color palette
            HStack(spacing: TTSpacing.xxs) {
                ForEach(colorPalette, id: \.self) { color in
                    Button(action: { selectedColor = color }) {
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.ttPrimary, lineWidth: selectedColor == color ? 1.5 : 0)
                                    .padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                ColorPicker("", selection: $selectedColor)
                    .labelsHidden()
                    .frame(width: 22, height: 22)

                // Custom saved colors
                if !customColors.isEmpty {
                    Divider().frame(height: 16).padding(.horizontal, TTSpacing.xxxs)
                    ForEach(Array(customColors.enumerated()), id: \.offset) { _, color in
                        Button(action: { selectedColor = color }) {
                            Circle()
                                .fill(color)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                                .overlay(Circle().stroke(Color.ttPrimary, lineWidth: selectedColor == color ? 1.5 : 0).padding(-2))
                        }
                        .buttonStyle(.plain)
                        .help("Custom color (right-click palette + to manage)")
                    }
                }

                // Save current color as a preset
                Button(action: saveCurrentColorPreset) {
                    Image(systemName: "plus.circle")
                        .font(.ttIcon(TTIcon.md))
                        .foregroundColor(.ttTextTertiary)
                }
                .buttonStyle(.plain)
                .help("Save current color as preset")

                if !customColors.isEmpty {
                    Button(action: { customColorsHex = "" }) {
                        Image(systemName: "xmark.circle")
                            .font(.ttIcon(TTIcon.sm))
                            .foregroundColor(.ttTextMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Clear custom colors")
                }
            }

            Divider().frame(height: 20).padding(.horizontal, TTSpacing.xxs)
            
            // Line width
            HStack(spacing: TTSpacing.xs) {
                Text("Size")
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextTertiary)
                
                ForEach([2, 4, 8], id: \.self) { w in
                    Button(action: { lineWidth = CGFloat(w) }) {
                        Circle()
                            .fill(Int(lineWidth) == w ? selectedColor : Color.ttTextTertiary)
                            .frame(width: CGFloat(max(w + 2, 6)), height: CGFloat(max(w + 2, 6)))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Int(lineWidth) == w ? selectedColor.opacity(0.1) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                Slider(value: $lineWidth, in: 1...12, step: 0.5)
                    .frame(width: 60)
                
                Text("\(lineWidth, specifier: "%.0f")px")
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextTertiary)
                    .frame(width: 28, alignment: .leading)
            }
            
            Spacer()
            
            // Zoom controls
            HStack(spacing: TTSpacing.xxs) {
                Button(action: zoomToFit) {
                    Text("Fit").font(TTFont.labelSmall)
                }
                .buttonStyle(.ttGhost)
                .keyboardShortcut("0", modifiers: .command)
                
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoomScale = min(zoomScale * 1.5, 10.0)
                        accumulatedZoom = zoomScale
                    }
                }) {
                    Image(systemName: "plus.magnifyingglass").font(.ttIcon(TTIcon.md))
                }
                .buttonStyle(.ttGhost)
                .keyboardShortcut("=", modifiers: .command)
                
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoomScale = max(zoomScale / 1.5, 0.1)
                        accumulatedZoom = zoomScale
                    }
                }) {
                    Image(systemName: "minus.magnifyingglass").font(.ttIcon(TTIcon.md))
                }
                .buttonStyle(.ttGhost)
                .keyboardShortcut("-", modifiers: .command)
                
                Text("\(Int(zoomScale * 100))%")
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextTertiary)
                    .frame(width: 36)
            }
        }
        .padding(.horizontal, TTSpacing.inputPaddingH)
        .padding(.vertical, TTSpacing.tight)
        .background(Color.ttSurface.opacity(0.7))
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Canvas Area
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // Architecture:  The DragGesture for drawing is placed on an overlay
    // that lives INSIDE the scaleEffect/offset transforms. This means
    // the gesture coordinates are already in the Canvas's local coordinate
    // space — NO conversion math needed.
    //
    // Zoom and pan gestures are on the outer container so they don't
    // interfere with drawing.
    //
    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack {
                // Dark canvas background
                Color(nsColor: NSColor(calibratedWhite: 0.08, alpha: 1.0))
                
                // Zoomable + pannable content
                imageAndCanvas(in: geo.size)
                    .scaleEffect(zoomScale, anchor: .center)
                    .offset(x: panOffset.width, y: panOffset.height)
            }
            .clipped()
            // Pinch-to-zoom on container
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoomScale = max(0.1, min(10.0, accumulatedZoom * value))
                    }
                    .onEnded { _ in
                        accumulatedZoom = zoomScale
                    }
            )
            // Scroll-wheel zoom
            .onScrollGesture { delta in
                let newZoom = zoomScale * (1.0 + delta * 0.02)
                withAnimation(.easeOut(duration: 0.1)) {
                    zoomScale = max(0.1, min(10.0, newZoom))
                    accumulatedZoom = zoomScale
                }
            }
        }
    }
    
    /// Image + Canvas + drawing gesture overlay — all in the same coordinate space
    private func imageAndCanvas(in containerSize: CGSize) -> some View {
        let imgSize = baseImage.size
        let availW = max(containerSize.width - 40, 100)
        let availH = max(containerSize.height - 40, 100)
        let fitScale = min(availW / imgSize.width, availH / imgSize.height)
        let fitW = imgSize.width * fitScale
        let fitH = imgSize.height * fitScale
        
        return ZStack {
            // Base image
            Image(nsImage: baseImage)
                .resizable()
                .frame(width: fitW, height: fitH)
            
            // Annotations canvas — exact same frame as image
            Canvas { context, size in
                for annotation in annotations {
                    renderAnnotation(annotation, in: &context, size: size)
                }
                // Live drag preview
                if !currentDragPoints.isEmpty {
                    var current = AnnotationItem(
                        tool: selectedTool, points: currentDragPoints,
                        color: selectedColor, lineWidth: lineWidth
                    )
                    if selectedTool == .stepCounter {
                        current.stepNumber = stepCounter + 1
                    }
                    current.isFilled = fillShape
                    renderAnnotation(current, in: &context, size: size)
                }
                // Selection highlight + resize handles
                if let sel = selectedAnnotation {
                    drawSelectionOverlay(sel, in: &context)
                }
            }
            .frame(width: fitW, height: fitH)

            // Transparent gesture overlay — same frame.
            // Gesture coords are in THIS view's local space = Canvas space.
            Color.clear
                .frame(width: fitW, height: fitH)
                .contentShape(Rectangle())
                .gesture(drawGesture, isEnabled: !isSelectMode)
                .gesture(selectGesture, isEnabled: isSelectMode)
        }
        // Report fitted canvas size so the host can scale annotations on export.
        .onAppear { onCanvasSizeChange?(CGSize(width: fitW, height: fitH)) }
        .onChange(of: containerSize) { _, _ in
            onCanvasSizeChange?(CGSize(width: fitW, height: fitH))
        }
        // Option+Drag panning (on the outer padding area too)
        .padding(TTSpacing.xl)
        .contentShape(Rectangle())
        .gesture(panGesture)
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Gestures
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /// Drawing gesture — coordinates are in Canvas local space (no conversion needed)
    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // If Option key is held, ignore drawing (panning takes over)
                if NSEvent.modifierFlags.contains(.option) { return }
                
                switch selectedTool {
                case .text:
                    textPosition = value.location
                case .stepCounter:
                    if currentDragPoints.isEmpty {
                        currentDragPoints = [value.location]
                    }
                case .blur, .spotlight, .rectangle, .ellipse, .arrow, .line:
                    currentDragPoints = [value.startLocation, value.location]
                case .eraser:
                    eraseAnnotationAt(value.location)
                default:
                    // pen, marker, highlight — append points for freehand
                    currentDragPoints.append(value.location)
                }
            }
            .onEnded { _ in
                if NSEvent.modifierFlags.contains(.option) { return }
                handleDragEnd()
            }
    }
    
    /// Pan gesture — Option+drag moves the canvas
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .modifiers(.option)
            .onChanged { value in
                panOffset = CGSize(
                    width: lastPanOffset.width + value.translation.width,
                    height: lastPanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastPanOffset = panOffset
            }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Selection / Move / Resize (Item 3)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var selectGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if NSEvent.modifierFlags.contains(.option) { return } // pan takes over
                if moveStartPoints == nil && resizeHandle == nil {
                    // First event of this drag — decide what we grabbed
                    if let sel = selectedAnnotation,
                       let handle = handleHitTest(value.startLocation, annotation: sel) {
                        resizeHandle = handle
                        moveStartPoints = sel.points
                    } else if let id = hitTest(value.startLocation) {
                        selectedAnnotationID = id
                        moveStartPoints = annotations.first { $0.id == id }?.points
                    } else {
                        selectedAnnotationID = nil
                        moveStartPoints = nil
                        return
                    }
                }
                applySelectionDrag(translation: value.translation)
            }
            .onEnded { _ in
                moveStartPoints = nil
                resizeHandle = nil
            }
    }

    private func applySelectionDrag(translation: CGSize) {
        guard let id = selectedAnnotationID,
              let idx = annotations.firstIndex(where: { $0.id == id }),
              let start = moveStartPoints else { return }
        if let h = resizeHandle, h < start.count {
            var pts = start
            pts[h] = CGPoint(x: start[h].x + translation.width, y: start[h].y + translation.height)
            annotations[idx].points = pts
        } else {
            annotations[idx].points = start.map {
                CGPoint(x: $0.x + translation.width, y: $0.y + translation.height)
            }
        }
        redoStack.removeAll()
    }

    /// Topmost annotation under `point`, or nil.
    private func hitTest(_ point: CGPoint) -> UUID? {
        for annotation in annotations.reversed() where isPoint(point, near: annotation) {
            return annotation.id
        }
        return nil
    }

    private func isPoint(_ point: CGPoint, near annotation: AnnotationItem) -> Bool {
        let tol: CGFloat = max(10, annotation.lineWidth + 8)
        switch annotation.tool {
        case .rectangle, .ellipse, .blur, .spotlight:
            guard let r = annotation.boundingRect else { return false }
            return r.insetBy(dx: -tol, dy: -tol).contains(point)
        case .text:
            guard let p = annotation.points.first else { return false }
            let fontSize = DesignSystemConfig.shared.annotationFontSize(
                lineWidth: annotation.lineWidth, multiplier: 4, minimumBase: 14
            )
            let w = CGFloat(max(4, annotation.text.count)) * fontSize * 0.62
            let h = fontSize * 1.5
            return CGRect(x: p.x, y: p.y, width: w, height: h).insetBy(dx: -tol, dy: -tol).contains(point)
        case .stepCounter:
            guard let p = annotation.points.first else { return false }
            let r = DesignSystemConfig.shared.annotationFontSize(
                lineWidth: annotation.lineWidth, multiplier: 3, minimumBase: 14
            )
            return hypot(point.x - p.x, point.y - p.y) <= r + tol
        default: // pen / marker / highlight / line / arrow
            return annotation.points.contains { hypot($0.x - point.x, $0.y - point.y) <= tol }
        }
    }

    /// Returns the index of a draggable resize handle near `point`, if any.
    private func handleHitTest(_ point: CGPoint, annotation: AnnotationItem) -> Int? {
        guard resizableShapes.contains(annotation.tool), annotation.points.count >= 2 else { return nil }
        let r: CGFloat = 12
        for (i, p) in annotation.points.enumerated() where hypot(p.x - point.x, p.y - point.y) <= r {
            return i
        }
        return nil
    }

    private func applyToSelection(_ mutate: (inout AnnotationItem) -> Void) {
        guard isSelectMode, let id = selectedAnnotationID,
              let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        mutate(&annotations[idx])
    }

    private func deleteSelection() {
        guard let id = selectedAnnotationID,
              let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        let removed = annotations.remove(at: idx)
        redoStack.append(removed)
        if removed.tool == .stepCounter { stepCounter = max(0, stepCounter - 1) }
        selectedAnnotationID = nil
    }

    private func beginTextEdit() {
        guard let sel = selectedAnnotation, sel.tool == .text else { return }
        editingTextID = sel.id
        textInput = sel.text
        textPosition = sel.points.first ?? .zero
        showTextInput = true
    }

    private func saveCurrentColorPreset() {
        let hex = selectedColor.hexRGB
        var list = customColorsHex.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        guard !list.contains(hex) else { return }
        list.append(hex)
        if list.count > 8 { list.removeFirst(list.count - 8) }
        customColorsHex = list.joined(separator: ",")
    }

    // MARK: - Selection Overlay Drawing
    private func drawSelectionOverlay(_ annotation: AnnotationItem, in context: inout GraphicsContext) {
        let accent = Color.ttPrimary
        let dashed = StrokeStyle(lineWidth: 1.5, dash: [5, 3])

        if resizableShapes.contains(annotation.tool), let rect = annotation.boundingRect {
            context.stroke(Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 4),
                           with: .color(accent), style: dashed)
            for p in [annotation.points.first, annotation.points.last].compactMap({ $0 }) {
                let hp = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: hp), with: .color(.white))
                context.stroke(Path(ellipseIn: hp), with: .color(accent), lineWidth: 1.5)
            }
        } else if let box = selectionBox(for: annotation) {
            context.stroke(Path(roundedRect: box.insetBy(dx: -4, dy: -4), cornerRadius: 4),
                           with: .color(accent), style: dashed)
        }
    }

    private func selectionBox(for annotation: AnnotationItem) -> CGRect? {
        switch annotation.tool {
        case .text:
            guard let p = annotation.points.first else { return nil }
            let fontSize = DesignSystemConfig.shared.annotationFontSize(
                lineWidth: annotation.lineWidth, multiplier: 4, minimumBase: 14
            )
            let w = CGFloat(max(4, annotation.text.count)) * fontSize * 0.62
            return CGRect(x: p.x, y: p.y, width: w, height: fontSize * 1.4)
        case .stepCounter:
            guard let p = annotation.points.first else { return nil }
            let r = DesignSystemConfig.shared.annotationFontSize(
                lineWidth: annotation.lineWidth, multiplier: 3, minimumBase: 14
            )
            return CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        default:
            guard let first = annotation.points.first else { return nil }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for p in annotation.points {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Drag End Handling
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private func handleDragEnd() {
        switch selectedTool {
        case .text:
            showTextInput = true
        case .stepCounter:
            if let pos = currentDragPoints.first {
                stepCounter += 1
                var annotation = AnnotationItem(
                    tool: .stepCounter, points: [pos],
                    color: selectedColor, lineWidth: lineWidth
                )
                annotation.stepNumber = stepCounter
                annotations.append(annotation)
                redoStack.removeAll()
            }
        case .eraser:
            break
        default:
            if currentDragPoints.count >= 2 {
                var annotation = AnnotationItem(
                    tool: selectedTool, points: currentDragPoints,
                    color: selectedColor, lineWidth: lineWidth
                )
                annotation.isFilled = fillShape
                annotations.append(annotation)
                redoStack.removeAll()
            }
        }
        currentDragPoints.removeAll()
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Eraser
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private func eraseAnnotationAt(_ point: CGPoint) {
        let hitRadius: CGFloat = 15
        if let index = annotations.lastIndex(where: { annotation in
            annotation.points.contains { p in
                hypot(p.x - point.x, p.y - point.y) < hitRadius
            }
        }) {
            let removed = annotations.remove(at: index)
            redoStack.append(removed)
            if removed.tool == .stepCounter { stepCounter = max(0, stepCounter - 1) }
        }
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Undo/Redo
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private func localUndo() {
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
        if last.tool == .stepCounter { stepCounter = max(0, stepCounter - 1) }
    }
    
    private func localRedo() {
        guard let last = redoStack.popLast() else { return }
        annotations.append(last)
        if last.tool == .stepCounter { stepCounter += 1 }
    }
    
    private func zoomToFit() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoomScale = 1.0
            accumulatedZoom = 1.0
            panOffset = .zero
            lastPanOffset = .zero
        }
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Text Input Overlay
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var textInputOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismissTextInput() }
            
            VStack(spacing: TTSpacing.lg) {
                HStack {
                    Image(systemName: "textformat")
                        .font(.ttIcon(TTIcon.xl))
                        .foregroundColor(.ttPrimary)
                    Text(editingTextID == nil ? "Add Text Annotation" : "Edit Text Annotation")
                        .font(TTFont.heading3)
                        .foregroundColor(.ttTextPrimary)
                    Spacer()
                    Button(action: { dismissTextInput() }) {
                        Image(systemName: "xmark")
                            .font(TTFont.labelMedium)
                            .foregroundColor(.ttTextTertiary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.ttSurface))
                    }
                    .buttonStyle(.plain)
                }
                
                AnnotationTextField(text: $textInput, placeholder: "Type your annotation text...", onCommit: commitText)
                    .frame(height: 36)
                
                HStack {
                    HStack(spacing: TTSpacing.xs) {
                        Circle().fill(selectedColor).frame(width: 14, height: 14)
                        Text("Color").font(TTFont.labelSmall).foregroundColor(.ttTextTertiary)
                    }
                    
                    Spacer()
                    
                    Button("Cancel") { dismissTextInput() }
                    .buttonStyle(.ttSecondaryCompact)

                    Button(editingTextID == nil ? "Add Text" : "Update") { commitText() }
                        .buttonStyle(.ttPrimaryCompact)
                        .disabled(textInput.isEmpty && editingTextID == nil)
                }
            }
            .padding(TTSpacing.xl)
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.ttSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.ttBorder, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeOut(duration: 0.15), value: showTextInput)
    }
    
    private func commitText() {
        // Re-editing an existing text annotation
        if let id = editingTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            if textInput.isEmpty {
                annotations.remove(at: idx)
                selectedAnnotationID = nil
            } else {
                annotations[idx].text = textInput
            }
            dismissTextInput()
            return
        }
        // New text annotation
        if !textInput.isEmpty {
            var annotation = AnnotationItem(
                tool: .text, points: [textPosition],
                color: selectedColor, lineWidth: lineWidth
            )
            annotation.text = textInput
            annotations.append(annotation)
            redoStack.removeAll()
        }
        dismissTextInput()
    }

    private func dismissTextInput() {
        showTextInput = false
        textInput = ""
        editingTextID = nil
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Bottom Status Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var bottomStatusBar: some View {
        HStack {
            Image(systemName: isSelectMode ? "cursorarrow" : selectedTool.icon)
                .font(.ttIcon(TTIcon.md))
                .foregroundColor(.ttPrimary)
            Text(statusText)
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextTertiary)

            // Contextual actions for the current selection
            if isSelectMode, let sel = selectedAnnotation {
                if sel.tool == .text {
                    Button(action: beginTextEdit) {
                        HStack(spacing: TTSpacing.inlineGapSmall) {
                            Image(systemName: "pencil").font(TTFont.badge)
                            Text("Edit Text").font(TTFont.labelSmall)
                        }
                    }
                    .buttonStyle(.ttGhost)
                }
                Button(action: deleteSelection) {
                    HStack(spacing: TTSpacing.inlineGapSmall) {
                        Image(systemName: "trash").font(TTFont.badge)
                        Text("Delete").font(TTFont.labelSmall)
                    }
                    .foregroundColor(.ttError)
                }
                .buttonStyle(.ttGhost)
                .keyboardShortcut(.delete, modifiers: [])
            }

            Spacer()

            Text("⌥+Drag: Pan  •  ⌘+/–: Zoom")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextMuted)
            
            Text("•").foregroundColor(.ttTextTertiary)
            
            Text("\(annotations.count) annotation\(annotations.count == 1 ? "" : "s")")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
            
            Text("•").foregroundColor(.ttTextTertiary)
            
            Text("\(Int(zoomScale * 100))%")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
            
            Text("•").foregroundColor(.ttTextTertiary)
            
            Text("\(Int(baseImage.size.width))×\(Int(baseImage.size.height))")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
        }
        .padding(.horizontal, TTSpacing.md)
        .padding(.vertical, TTSpacing.xs)
        .background(Color.ttSurface.opacity(0.9))
    }
    
    private var statusText: String {
        if isSelectMode {
            return selectedAnnotation == nil
                ? "Select — tap an annotation to select it"
                : "Drag to move • drag a handle to resize • change color/size to restyle"
        }
        switch selectedTool {
        case .pen: return "Pen — draw smooth freehand strokes"
        case .marker: return "Marker — thick semi-transparent strokes"
        case .arrow: return "Drag to draw an arrow"
        case .line: return "Drag to draw a straight line"
        case .rectangle: return fillShape ? "Drag to draw a filled rectangle" : "Drag to draw a rectangle"
        case .ellipse: return fillShape ? "Drag to draw a filled ellipse" : "Drag to draw an ellipse"
        case .text: return "Click to place text annotation"
        case .stepCounter: return "Click to place step \(stepCounter + 1)"
        case .blur: return "Drag to blur a region"
        case .highlight: return "Draw to highlight"
        case .spotlight: return "Drag to spotlight a region"
        case .eraser: return "Click on annotation to erase"
        }
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Render Annotation (delegates to shared canvas renderer)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private func renderAnnotation(_ annotation: AnnotationItem, in context: inout GraphicsContext, size: CGSize) {
        AnnotationCanvasRenderer.draw(annotation, in: &context, size: size)
    }
}

// MARK: - Color → Hex (for custom-color persistence)
private extension Color {
    /// "#RRGGBB" string for storing presets in @AppStorage.
    var hexRGB: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.red
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Preview
#Preview {
    AnnotationEditorView(
        baseImage: NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage(),
        annotations: .constant([]),
        onDone: {},
        onCancel: {}
    )
    .frame(width: 1200, height: 900)
    .preferredColorScheme(.dark)
}
