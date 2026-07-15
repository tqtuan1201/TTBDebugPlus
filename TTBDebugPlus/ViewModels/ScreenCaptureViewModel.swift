//
//  ScreenCaptureViewModel.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Manages screenshot capture, recording sessions, GIF export, gallery & annotations
//

import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Screen Capture ViewModel
@Observable
final class ScreenCaptureViewModel {
    
    // MARK: - Screenshot State
    var currentScreenshot: NSImage? = nil
    var screenshotHistory: [ScreenshotItem] = []
    var isCapturing: Bool = false
    var selectedHistoryItem: ScreenshotItem? = nil
    
    // MARK: - Gallery State
    var selectedItems: Set<UUID> = []
    var isMultiSelectMode: Bool = false
    var galleryViewMode: GalleryViewMode = .grid
    var sortOrder: GallerySortOrder = .newest
    
    // MARK: - Annotation State
    var isAnnotating: Bool = false
    var annotations: [AnnotationItem] = []
    var selectedTool: AnnotationTool = .pen
    var selectedColor: Color = .red
    var lineWidth: CGFloat = 3.0
    
    // MARK: - Recording State
    var recordingSession = RecordingSession()
    var recordingElapsed: TimeInterval = 0
    var showRecordingExport: Bool = false
    
    // MARK: - Bug Report State
    var showBugReportComposer: Bool = false
    var reportScreenshots: [NSImage] = []
    
    // MARK: - Fullscreen Preview
    var isFullscreenPreview: Bool = false
    
    // MARK: - Private
    private var recordingSource: DispatchSourceTimer?
    private var elapsedTimer: Timer?
    private let maxHistoryCount = 50
    private let maxRecordingFrames = 600
    private let timerQueue = DispatchQueue(label: "com.ttbdebug.recording", qos: .utility)
    /// Bumps on each capture request so stale timeouts cannot clear a newer capture.
    private var captureGeneration: UInt64 = 0
    /// Last screenshot timestamp applied (dedupe rapid onChange fires).
    private var lastHandledScreenshotKey: String?
    /// Weak ref for recording ticks — avoids retaining ConnectionManager via timer.
    private weak var recordingConnectionManager: ConnectionManager?

    deinit {
        recordingSource?.cancel()
        elapsedTimer?.invalidate()
    }
    
    // MARK: - Computed
    var sortedHistory: [ScreenshotItem] {
        switch sortOrder {
        case .newest: return screenshotHistory
        case .oldest: return screenshotHistory.reversed()
        }
    }
    
    var selectedCount: Int { selectedItems.count }
    var hasSelection: Bool { !selectedItems.isEmpty }
    var isRecording: Bool { recordingSession.isActive }
    
    // MARK: - Capture Screenshot
    func requestCapture(from connectionManager: ConnectionManager) {
        // Prefer lifecycle + live selected device (not only port-bound isServerRunning)
        let deviceOnline = connectionManager.selectedDevice?.isOnline(relativeTo: connectionManager.uiNow) == true
        guard connectionManager.isLifecycleActive, deviceOnline else {
            isCapturing = false
            if recordingSession.isActive {
                stopRecording()
            }
            return
        }
        // During recording allow pipelined requests; single capture still serializes.
        if !isRecording {
            guard !isCapturing else { return }
        }
        isCapturing = true
        captureGeneration &+= 1
        let generation = captureGeneration
        
        let quality = isRecording ? 0.4 : 0.7
        let maxWidth = isRecording ? 750 : 1170
        connectionManager.requestScreenshot(quality: quality, maxWidth: maxWidth)
        
        // Timeout fallback — only clear if this generation is still current
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.captureGeneration == generation else { return }
            self.isCapturing = false
        }
    }
    
    // MARK: - Handle Received Screenshot
    func handleScreenshotReceived(_ response: ScreenshotResponsePayload) {
        let key = "\(response.timestamp)-\(response.imageData.count)"
        guard lastHandledScreenshotKey != key else { return }
        lastHandledScreenshotKey = key
        isCapturing = false
        
        // Decode image on background queue to avoid blocking main thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let imageData = Data(base64Encoded: response.imageData),
                  let image = NSImage(data: imageData) else {
                print("[TTBDebug] Failed to decode screenshot")
                return
            }
            
            let item = ScreenshotItem(
                image: image,
                timestamp: Date(timeIntervalSince1970: response.timestamp / 1000),
                orientation: response.orientation,
                screenSize: CGSize(width: response.screenWidth, height: response.screenHeight)
            )
            
            DispatchQueue.main.async {
                self.currentScreenshot = image
                self.screenshotHistory.insert(item, at: 0)
                self.selectedHistoryItem = item
                
                // Add to recording session
                if self.recordingSession.isActive {
                    guard self.recordingSession.frames.count < self.maxRecordingFrames else {
                        self.stopRecording()
                        return
                    }
                    let frame = RecordingFrame(
                        image: image,
                        timestamp: Date(),
                        index: self.recordingSession.frameCount
                    )
                    self.recordingSession.frames.append(frame)
                }
                
                // Trim history
                if self.screenshotHistory.count > self.maxHistoryCount {
                    self.screenshotHistory = Array(self.screenshotHistory.prefix(self.maxHistoryCount))
                }
            }
        }
    }
    
    // MARK: - Recording
    func startRecording(connectionManager: ConnectionManager, interval: TimeInterval = 0.5) {
        guard !recordingSession.isActive else { return }
        guard connectionManager.isLifecycleActive,
              connectionManager.selectedDevice?.isOnline(relativeTo: connectionManager.uiNow) == true else {
            return
        }
        recordingSession = RecordingSession()
        recordingSession.isActive = true
        recordingSession.interval = interval
        recordingSession.startTime = Date()
        recordingElapsed = 0
        
        // Use DispatchSourceTimer on background queue to avoid main thread blocking.
        recordingConnectionManager = connectionManager
        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let cm = self.recordingConnectionManager else {
                    self.stopRecording()
                    return
                }
                self.requestCapture(from: cm)
            }
        }
        source.resume()
        recordingSource = source
        
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.recordingSession.isActive else { return }
            self.recordingElapsed = Date().timeIntervalSince(self.recordingSession.startTime)
        }
        elapsedTimer?.tolerance = 0.2
        
        // Capture first frame immediately
        requestCapture(from: connectionManager)
    }
    
    func stopRecording() {
        recordingSession.isActive = false
        recordingSource?.cancel()
        recordingSource = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordingConnectionManager = nil
        
        if recordingSession.frameCount > 0 {
            showRecordingExport = true
        }
    }

    /// Call when selected device disconnects or changes to avoid cross-device frames.
    func handleDeviceContextLost() {
        if recordingSession.isActive {
            stopRecording()
        }
        isCapturing = false
        captureGeneration &+= 1
        recordingConnectionManager = nil
    }
    
    var formattedRecordingTime: String {
        let mins = Int(recordingElapsed) / 60
        let secs = Int(recordingElapsed) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - GIF Export
    func exportGIF(speed: Double = 1.0) -> URL? {
        let frames = recordingSession.frames.compactMap { $0.image }
        guard !frames.isEmpty else { return nil }
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TTBDebug_\(Int(Date().timeIntervalSince1970)).gif")
        
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return nil }
        
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
        
        let frameDelay = recordingSession.interval / speed
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]
        
        for frame in frames {
            if let cgImage = frame.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            }
        }
        
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }
    
    func exportImageSequence() -> URL? {
        let frames = recordingSession.frames.compactMap { $0.image }
        guard !frames.isEmpty else { return nil }
        
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TTBDebug_Sequence_\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        for (i, image) in frames.enumerated() {
            let fileName = String(format: "frame_%04d.png", i)
            let fileURL = dir.appendingPathComponent(fileName)
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
            }
        }
        
        return dir
    }
    
    func discardRecording() {
        recordingSession.reset()
        recordingElapsed = 0
        showRecordingExport = false
    }
    
    // MARK: - Gallery Management
    func selectItem(_ item: ScreenshotItem) {
        currentScreenshot = item.image
        selectedHistoryItem = item
    }
    
    func toggleSelection(_ id: UUID) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }
    
    func selectAll() {
        selectedItems = Set(screenshotHistory.map { $0.id })
    }
    
    func deselectAll() {
        selectedItems.removeAll()
        isMultiSelectMode = false
    }
    
    func deleteSelected() {
        screenshotHistory.removeAll { selectedItems.contains($0.id) }
        if let current = selectedHistoryItem, selectedItems.contains(current.id) {
            selectedHistoryItem = screenshotHistory.first
            currentScreenshot = screenshotHistory.first?.image
        }
        selectedItems.removeAll()
        isMultiSelectMode = false
    }
    
    func deleteItem(_ id: UUID) {
        screenshotHistory.removeAll { $0.id == id }
        if selectedHistoryItem?.id == id {
            selectedHistoryItem = screenshotHistory.first
            currentScreenshot = screenshotHistory.first?.image
        }
    }
    
    func clearAllHistory() {
        screenshotHistory.removeAll()
        selectedItems.removeAll()
        selectedHistoryItem = nil
        currentScreenshot = nil
        isMultiSelectMode = false
    }
    
    // MARK: - Export
    @MainActor
    func exportScreenshot(withAnnotations: Bool = false) -> URL? {
        guard let image = currentScreenshot else { return nil }
        
        let finalImage: NSImage
        if withAnnotations && !annotations.isEmpty {
            finalImage = renderAnnotatedImage(baseImage: image)
        } else {
            finalImage = image
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "TTBDebug_\(Int(Date().timeIntervalSince1970)).png"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        if let tiffData = finalImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
            return fileURL
        }
        return nil
    }
    
    func exportItem(_ item: ScreenshotItem) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        let fileName = "TTBDebug_\(formatter.string(from: item.timestamp))_\(item.id.uuidString.prefix(4)).png"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        if let tiffData = item.image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
            return fileURL
        }
        return nil
    }
    
    func exportSelected() -> [URL] {
        screenshotHistory
            .filter { selectedItems.contains($0.id) }
            .compactMap { exportItem($0) }
    }
    
    func exportAll() -> [URL] {
        screenshotHistory.compactMap { exportItem($0) }
    }
    
    // MARK: - Bug Report
    func openBugReport(with images: [NSImage]? = nil) {
        if let images {
            reportScreenshots = images
        } else if let current = currentScreenshot {
            reportScreenshots = [current]
        }
        showBugReportComposer = true
    }
    
    func openBugReportFromSelected() {
        let images = screenshotHistory
            .filter { selectedItems.contains($0.id) }
            .map { $0.image }
        openBugReport(with: images)
    }
    
    // MARK: - Annotation Rendering (SwiftUI ImageRenderer — pixel-identical to editor)
    //
    // Annotations are authored in a *fitted display* coordinate space (the editor
    // canvas or the small preview). We scale their points to full image pixels and
    // re-draw them with the SAME SwiftUI Canvas code the editor uses (AnnotationCanvasRenderer),
    // so the exported image matches exactly — no bottom-left/top-left Y-flip drift.

    /// Scales annotations from a display coordinate space to full image pixels.
    func scaleAnnotations(_ items: [AnnotationItem], from displaySize: CGSize, to pixel: CGSize) -> [AnnotationItem] {
        guard displaySize.width > 0, displaySize.height > 0 else { return items }
        let sx = pixel.width / displaySize.width
        let sy = pixel.height / displaySize.height
        let s = max(sx, sy)
        return items.map { item in
            var c = item
            c.points = item.points.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
            c.lineWidth = item.lineWidth * s
            return c
        }
    }

    /// Renders `annotationsInPixels` (already in image-pixel coords) onto `baseImage`.
    @MainActor
    func composeAnnotatedImage(baseImage: NSImage, annotationsInPixels: [AnnotationItem]) -> NSImage {
        guard !annotationsInPixels.isEmpty else { return baseImage }
        let px = pixelSize(of: baseImage)
        guard px.width > 0, px.height > 0 else { return baseImage }

        let view = AnnotatedImageRender(
            baseImage: baseImage,
            annotations: annotationsInPixels,
            width: px.width,
            height: px.height
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1 // size is already in pixels
        return renderer.nsImage ?? baseImage
    }

    /// Back-compat: render the editor's own `annotations` onto an image, given the
    /// editor canvas display size (pass `.zero` to treat annotations as already 1:1).
    @MainActor
    func renderAnnotatedImage(baseImage: NSImage, displaySize: CGSize = .zero) -> NSImage {
        let px = pixelSize(of: baseImage)
        let source = displaySize.width > 0 ? displaySize : px
        return composeAnnotatedImage(baseImage: baseImage, annotationsInPixels: scaleAnnotations(annotations, from: source, to: px))
    }

    /// Renders annotations drawn in a display-sized preview onto the full-resolution image.
    @MainActor
    func renderImageWithQuickAnnotations(
        baseImage: NSImage,
        annotations: [AnnotationItem],
        displaySize: CGSize
    ) -> NSImage {
        let px = pixelSize(of: baseImage)
        return composeAnnotatedImage(baseImage: baseImage, annotationsInPixels: scaleAnnotations(annotations, from: displaySize, to: px))
    }

    // MARK: - Device-Info Footer Banner (for "Copy + Info")
    /// Pixel dimensions of an NSImage (falls back to point size).
    func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first {
            let w = rep.pixelsWide, h = rep.pixelsHigh
            if w > 0 && h > 0 { return CGSize(width: w, height: h) }
        }
        return image.size
    }

    /// Composites a device-info footer banner BELOW `image`.
    /// `image` should ALREADY contain any rendered annotations.
    @MainActor
    func imageWithInfoFooter(_ image: NSImage, deviceInfo: DeviceInfoSnapshot, timestamp: Date) -> NSImage {
        let basePx = pixelSize(of: image)
        guard basePx.width > 0, basePx.height > 0 else { return image }

        // Footer scale tracks image width so text stays legible at full resolution.
        let scale = max(1.0, basePx.width / 1170.0)
        let footerView = ScreenshotInfoFooterView(info: deviceInfo, timestamp: timestamp, scale: scale)
            .frame(width: basePx.width)
            .fixedSize(horizontal: false, vertical: true)

        let renderer = ImageRenderer(content: footerView)
        renderer.scale = 1 // work directly in pixel units
        guard let footerImage = renderer.nsImage else { return image }
        let footerH = footerImage.size.height

        let total = CGSize(width: basePx.width, height: basePx.height + footerH)
        let result = NSImage(size: total)
        result.lockFocus()
        // NSImage origin is bottom-left: image on top, footer underneath.
        image.draw(in: NSRect(x: 0, y: footerH, width: basePx.width, height: basePx.height))
        footerImage.draw(in: NSRect(x: 0, y: 0, width: basePx.width, height: footerH))
        result.unlockFocus()
        return result
    }

    // MARK: - Clipboard Helpers
    /// Copies an image to the pasteboard, optionally with a metadata text representation
    /// (so paste targets that prefer text — Slack/Jira fields — also receive context).
    func copyToPasteboard(image: NSImage, metadata: String? = nil) {
        let pb = NSPasteboard.general
        pb.clearContents()
        var objects: [NSPasteboardWriting] = [image]
        if let metadata, !metadata.isEmpty {
            objects.append(metadata as NSString)
        }
        pb.writeObjects(objects)
    }

}

// MARK: - Supporting Models

struct ScreenshotItem: Identifiable {
    let id = UUID()
    let image: NSImage
    let timestamp: Date
    let orientation: String
    let screenSize: CGSize
    
    // Pre-computed strings (avoid re-formatting each render)
    let formattedTime: String
    let formattedDateTime: String
    
    // Static DateFormatters — shared across all instances
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm:ss"
        return f
    }()
    
    init(image: NSImage, timestamp: Date, orientation: String, screenSize: CGSize) {
        self.image = image
        self.timestamp = timestamp
        self.orientation = orientation
        self.screenSize = screenSize
        self.formattedTime = Self.timeFormatter.string(from: timestamp)
        self.formattedDateTime = Self.dateTimeFormatter.string(from: timestamp)
    }
    
    var resolutionText: String { "\(Int(screenSize.width))×\(Int(screenSize.height))" }
    
    var fileSizeEstimate: String {
        // Rough estimate based on screen size (avoids expensive tiffRepresentation)
        let estimatedBytes = Int(screenSize.width * screenSize.height * 4 * 0.15) // ~15% of raw RGBA
        let kb = Double(estimatedBytes) / 1024
        return kb > 1024 ? String(format: "%.1f MB", kb / 1024) : String(format: "%.0f KB", kb)
    }
}

enum GalleryViewMode: String, CaseIterable {
    case grid = "Grid"
    case list = "List"
    var icon: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

enum GallerySortOrder: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
}

struct AnnotationItem: Identifiable {
    let id = UUID()
    let tool: AnnotationTool
    var points: [CGPoint]
    var color: Color          // mutable: re-color a selected annotation
    var lineWidth: CGFloat    // mutable: re-stroke a selected annotation
    var text: String = ""
    var stepNumber: Int = 0
    var isFilled: Bool = false

    /// Translate all points by a delta (used when dragging a selected annotation).
    mutating func translate(by delta: CGSize) {
        points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
    }
}

enum AnnotationTool: String, CaseIterable {
    case pen = "Pen"
    case marker = "Marker"
    case arrow = "Arrow"
    case line = "Line"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case text = "Text"
    case stepCounter = "Step Counter"
    case blur = "Blur"
    case highlight = "Highlight"
    case spotlight = "Spotlight"
    case eraser = "Eraser"
    
    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .marker: return "paintbrush.pointed.fill"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .stepCounter: return "number.circle"
        case .blur: return "checkerboard.rectangle"
        case .highlight: return "highlighter"
        case .spotlight: return "flashlight.on.fill"
        case .eraser: return "eraser"
        }
    }
    
    /// Short display name for toolbar button labels
    var shortName: String {
        switch self {
        case .pen: return "Pen"
        case .marker: return "Marker"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rect"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .stepCounter: return "Step"
        case .blur: return "Blur"
        case .highlight: return "Highlight"
        case .spotlight: return "Spot"
        case .eraser: return "Erase"
        }
    }
    
    /// Keyboard shortcut hint for tooltip
    var shortcutHint: String {
        switch self {
        case .pen: return "P"
        case .marker: return "M"
        case .arrow: return "A"
        case .line: return "L"
        case .rectangle: return "R"
        case .ellipse: return "O"
        case .text: return "T"
        case .stepCounter: return "N"
        case .blur: return "B"
        case .highlight: return "H"
        case .spotlight: return "S"
        case .eraser: return "E"
        }
    }
    
    var group: ToolGroup {
        switch self {
        case .pen, .marker, .highlight: return .draw
        case .arrow, .line, .rectangle, .ellipse: return .shape
        case .text, .stepCounter, .blur, .spotlight: return .annotate
        case .eraser: return .edit
        }
    }
    
    enum ToolGroup: String, CaseIterable {
        case draw = "Draw"
        case shape = "Shape"
        case annotate = "Annotate"
        case edit = "Edit"
    }
}

// MARK: - Annotated Image Renderer (SwiftUI → image)
/// Base screenshot + annotations drawn with the shared Canvas renderer.
/// Rendered to a bitmap via ImageRenderer so export matches the live editor exactly.
struct AnnotatedImageRender: View {
    let baseImage: NSImage
    let annotations: [AnnotationItem]  // already in image-pixel coordinates
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Image(nsImage: baseImage)
                .resizable()
                .frame(width: width, height: height)
            Canvas { context, size in
                for annotation in annotations {
                    AnnotationCanvasRenderer.draw(annotation, in: &context, size: size)
                }
            }
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Screenshot Info Footer Banner
/// Dark banner appended below a screenshot when exporting "Copy + Info".
/// Rendered via ImageRenderer — reads applied design metrics at render time
/// (export raster `scale` × Settings font/spacing scales).
struct ScreenshotInfoFooterView: View {
    let info: DeviceInfoSnapshot
    let timestamp: Date
    /// Raster / image export scale (independent of app density).
    var scale: CGFloat = 1.0
    var appTitle: String = "TTBDebugPlus"

    /// Composite: export scale × applied design metrics (Phase 5).
    private var fontMul: CGFloat {
        DesignSystemConfig.shared.exportFontScale(exportScale: scale)
    }
    private var spaceMul: CGFloat {
        DesignSystemConfig.shared.exportSpacingScale(exportScale: scale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * spaceMul) {
            // Row 1 — brand · capture time · device-type badge
            HStack(alignment: .center, spacing: 10 * spaceMul) {
                Image(systemName: AppIcon.app)
                    .font(.system(size: 19 * fontMul, weight: .semibold))
                    .foregroundColor(.ttError)
                Text(appTitle)
                    .font(.system(size: 15 * fontMul, weight: .bold))
                    .foregroundColor(.white)
                Text(info.formattedStamp(timestamp))
                    .font(.system(size: 12 * fontMul, weight: .regular).monospacedDigit())
                    .foregroundColor(.white.opacity(0.55))

                Spacer(minLength: 8 * spaceMul)

                Text(info.isSimulator ? "SIMULATOR" : "REAL DEVICE")
                    .font(.system(size: 11 * fontMul, weight: .bold))
                    .tracking(0.8 * fontMul)
                    .foregroundColor(info.isSimulator ? .ttWarning : .ttSuccess)
                    .padding(.horizontal, 9 * spaceMul)
                    .padding(.vertical, 4 * spaceMul)
                    .background(
                        RoundedRectangle(cornerRadius: 5 * spaceMul)
                            .fill((info.isSimulator ? Color.ttWarning : Color.ttSuccess).opacity(0.16))
                    )
            }

            // Row 2 — Device · OS · App · Screen · SDK (wraps if needed, never overlaps)
            infoText
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22 * spaceMul)
        .padding(.vertical, 15 * spaceMul)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: NSColor(calibratedWhite: 0.11, alpha: 1.0)))
    }

    /// Field pairs as a single concatenated Text — label dim, value bright,
    /// separated by a faint dot. Wraps cleanly inside ImageRenderer.
    private var infoText: Text {
        let pairs = info.displayPairs
        var result = Text("")
        for (i, pair) in pairs.enumerated() {
            if i > 0 {
                result = result + Text("   ·   ")
                    .font(.system(size: 13 * fontMul))
                    .foregroundColor(.white.opacity(0.3))
            }
            result = result
                + Text("\(pair.label)  ")
                    .font(.system(size: 11 * fontMul, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                + Text(pair.value)
                    .font(.system(size: 13 * fontMul, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
        }
        return result
    }
}
