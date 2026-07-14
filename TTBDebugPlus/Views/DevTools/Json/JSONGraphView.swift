//
//  JSONGraphView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Interactive graph visualization: pannable/zoomable canvas with JSON nodes & edges
//

import SwiftUI

struct JSONGraphView: View {
    let jsonString: String
    
    @State private var layout: GraphLayout = .empty
    @State private var isLoading: Bool = true
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var collapsedNodeIds: Set<String> = []
    @State private var selectedNodeId: String? = nil
    @State private var hoveredNodeId: String? = nil
    @State private var canvasSize: CGSize = .zero

    private enum DefaultsKey {
        static let scale = "devTools.jsonGraph.scale"
        static let offsetWidth = "devTools.jsonGraph.offsetWidth"
        static let offsetHeight = "devTools.jsonGraph.offsetHeight"
        static let collapsedNodeIds = "devTools.jsonGraph.collapsedNodeIds"
        static let selectedNodeId = "devTools.jsonGraph.selectedNodeId"
    }
    
    // Zoom limits
    private let minScale: CGFloat = 0.15
    private let maxScale: CGFloat = 2.5
    
    var body: some View {
        ZStack {
            // Background with subtle grid
            Color.ttBackground
                .ignoresSafeArea()
            
            if isLoading {
                loadingOverlay
            } else if layout.nodes.isEmpty {
                emptyState
            } else {
                graphCanvas
            }
            
            // Toolbar overlay
            VStack {
                HStack {
                    Spacer()
                    graphToolbar
                }
                .padding(12)
                Spacer()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: jsonString.hashValue) {
            await buildLayout()
        }
    }
    
    // MARK: - Graph Canvas
    private var graphCanvas: some View {
        GeometryReader { geometry in
            let totalOffset = CGSize(
                width: offset.width + dragOffset.width,
                height: offset.height + dragOffset.height
            )
            
            ZStack(alignment: .topLeading) {
                // Grid pattern background
                gridPattern(size: geometry.size, offset: totalOffset)
                    .allowsHitTesting(false)
                
                // Edge lines (drawn first, behind nodes)
                Canvas { context, _ in
                    drawEdges(context: context, offset: totalOffset)
                }
                .allowsHitTesting(false)
                
                // Nodes
                ForEach(visibleNodes) { node in
                    graphNodeView(node)
                        .position(
                            x: (node.position.x + node.size.width / 2) * scale + totalOffset.width,
                            y: (node.position.y + node.size.height / 2) * scale + totalOffset.height
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        dragOffset = .zero
                        saveViewportState()
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = scale * value
                        scale = max(minScale, min(maxScale, newScale))
                    }
                    .onEnded { _ in
                        saveViewportState()
                    }
            )
            .onAppear {
                canvasSize = geometry.size
                applyStoredViewportOrFit(size: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
            }
        }
    }
    
    // MARK: - Grid Pattern
    private func gridPattern(size: CGSize, offset: CGSize) -> some View {
        Canvas { context, canvasSize in
            let gridSize: CGFloat = 40 * scale
            guard gridSize > 5 else { return }
            
            let opacity = min(1.0, max(0.0, (gridSize - 5) / 20)) * 0.06
            
            let startX = offset.width.truncatingRemainder(dividingBy: gridSize)
            let startY = offset.height.truncatingRemainder(dividingBy: gridSize)
            
            var x = startX
            while x < canvasSize.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                context.stroke(path, with: .color(Color.ttBorder.opacity(opacity)), lineWidth: 0.5)
                x += gridSize
            }
            
            var y = startY
            while y < canvasSize.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                context.stroke(path, with: .color(Color.ttBorder.opacity(opacity)), lineWidth: 0.5)
                y += gridSize
            }
        }
    }
    
    // MARK: - Node View
    private func graphNodeView(_ node: GraphNode) -> some View {
        let nodeScale = max(0.5, scale) // Minimum visible scale for readability
        
        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                // Type badge
                Text(node.valueType.badge)
                    .font(.system(size: max(9, 10 * nodeScale), weight: .bold, design: .monospaced))
                    .foregroundColor(.ttTextOnAccent)
                
                Text(node.label)
                    .font(.system(size: max(9, 11 * nodeScale), weight: .semibold))
                    .foregroundColor(.ttTextOnAccent)
                    .lineLimit(1)
                
                Spacer()
                
                if !node.childIds.isEmpty {
                    HStack(spacing: 2) {
                        Text("\(node.childIds.count)")
                            .font(.system(size: max(7, 8 * nodeScale), weight: .bold, design: .monospaced))
                            .foregroundColor(.ttTextOnAccent.opacity(0.85))
                        Image(systemName: collapsedNodeIds.contains(node.id) ? "chevron.right" : "chevron.down")
                            .font(.system(size: max(7, 8 * nodeScale), weight: .bold))
                            .foregroundColor(.ttTextOnAccent.opacity(0.85))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                node.headerColor.opacity(0.85)
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.05), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            
            // Entries
            if !node.entries.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    let visibleEntries = Array(node.entries.prefix(8))
                    ForEach(Array(visibleEntries.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 4) {
                            Text(entry.key)
                                .foregroundColor(.ttJsonKey)
                            Text(":")
                                .foregroundColor(.ttJsonBrace.opacity(0.5))
                            Text(entry.value)
                                .foregroundColor(entry.type.badgeColor)
                                .lineLimit(1)
                        }
                        .font(.system(size: max(8, 10 * nodeScale), design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                    }
                    
                    if node.entries.count > 8 {
                        HStack(spacing: 3) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: max(7, 8 * nodeScale)))
                            Text("+\(node.entries.count - 8) more")
                                .font(.system(size: max(7, 9 * nodeScale), design: .monospaced))
                        }
                        .foregroundColor(.ttTextTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: max(120, node.size.width * scale))
        .background(
            RoundedRectangle(cornerRadius: max(6, 8 * scale))
                .fill(Color.ttSurface)
                .shadow(
                    color: selectedNodeId == node.id ? node.headerColor.opacity(0.4) : Color.black.opacity(0.2),
                    radius: selectedNodeId == node.id ? 10 : 4,
                    x: 0, y: 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: max(6, 8 * scale))
                .stroke(
                    selectedNodeId == node.id ? node.headerColor :
                    (hoveredNodeId == node.id ? Color.ttPrimary.opacity(0.5) : Color.ttBorder.opacity(0.3)),
                    lineWidth: selectedNodeId == node.id ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: max(6, 8 * scale)))
        .onHover { isHovered in
            hoveredNodeId = isHovered ? node.id : nil
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedNodeId = node.id
                if !node.childIds.isEmpty {
                    if collapsedNodeIds.contains(node.id) {
                        collapsedNodeIds.remove(node.id)
                    } else {
                        collapsedNodeIds.insert(node.id)
                    }
                }
                saveGraphState()
            }
        }
    }
    
    // MARK: - Edge Drawing
    private func drawEdges(context: GraphicsContext, offset: CGSize) {
        for edge in layout.edges {
            guard let fromNode = layout.nodes.first(where: { $0.id == edge.fromId }),
                  let toNode = layout.nodes.first(where: { $0.id == edge.toId }) else { continue }
            
            // Skip edges from collapsed nodes
            if collapsedNodeIds.contains(edge.fromId) { continue }
            
            let fromPoint = CGPoint(
                x: (fromNode.position.x + fromNode.size.width / 2) * scale + offset.width,
                y: (fromNode.position.y + fromNode.size.height) * scale + offset.height
            )
            let toPoint = CGPoint(
                x: (toNode.position.x + toNode.size.width / 2) * scale + offset.width,
                y: toNode.position.y * scale + offset.height
            )
            
            var path = Path()
            path.move(to: fromPoint)
            
            // Bezier curve for smooth edges
            let controlY = (fromPoint.y + toPoint.y) / 2
            path.addCurve(
                to: toPoint,
                control1: CGPoint(x: fromPoint.x, y: controlY),
                control2: CGPoint(x: toPoint.x, y: controlY)
            )
            
            let isHighlighted = selectedNodeId == edge.fromId || selectedNodeId == edge.toId
            context.stroke(
                path,
                with: .color(isHighlighted ? Color.ttPrimary : Color.ttBorder.opacity(0.35)),
                lineWidth: isHighlighted ? 2 : 1
            )
            
            // Arrow at endpoint
            let arrowSize: CGFloat = max(3, 5 * scale)
            var arrowPath = Path()
            arrowPath.move(to: CGPoint(x: toPoint.x - arrowSize, y: toPoint.y - arrowSize * 1.5))
            arrowPath.addLine(to: toPoint)
            arrowPath.addLine(to: CGPoint(x: toPoint.x + arrowSize, y: toPoint.y - arrowSize * 1.5))
            context.fill(
                arrowPath,
                with: .color(isHighlighted ? Color.ttPrimary : Color.ttBorder.opacity(0.35))
            )
        }
    }
    
    // MARK: - Visible Nodes (filtered by collapse state)
    private var visibleNodes: [GraphNode] {
        var hidden = Set<String>()
        for collapsedId in collapsedNodeIds {
            collectDescendants(collapsedId, hidden: &hidden)
        }
        return layout.nodes.filter { !hidden.contains($0.id) }
    }
    
    private func collectDescendants(_ nodeId: String, hidden: inout Set<String>) {
        guard let node = layout.nodes.first(where: { $0.id == nodeId }) else { return }
        for childId in node.childIds {
            hidden.insert(childId)
            collectDescendants(childId, hidden: &hidden)
        }
    }
    
    // MARK: - Graph Toolbar
    private var graphToolbar: some View {
        HStack(spacing: 5) {
            // Zoom controls
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scale = max(minScale, scale * 0.8)
                }
                saveViewportState()
            }) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 12))
            }
            .buttonStyle(.ttGhost)
            .help("Zoom Out")
            
            Text("\(Int(scale * 100))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.ttTextTertiary)
                .frame(width: 44)
                .monospacedDigit()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scale = min(maxScale, scale * 1.25)
                }
                saveViewportState()
            }) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 12))
            }
            .buttonStyle(.ttGhost)
            .help("Zoom In")
            
            Divider().frame(height: 16)
            
            // Fit to window — uses stored canvasSize
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    fitToWindow(size: canvasSize)
                }
                saveViewportState()
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12))
            }
            .buttonStyle(.ttGhost)
            .help("Fit to Window")
            
            // Reset
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    scale = 1.0
                    offset = .zero
                }
                saveViewportState()
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.ttGhost)
            .help("Reset View")
            
            Divider().frame(height: 16)
            
            // Expand/Collapse all
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if collapsedNodeIds.isEmpty {
                        // Collapse all with children
                        for node in layout.nodes where !node.childIds.isEmpty {
                            collapsedNodeIds.insert(node.id)
                        }
                    } else {
                        collapsedNodeIds.removeAll()
                    }
                    saveGraphState()
                }
            }) {
                Image(systemName: collapsedNodeIds.isEmpty ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .font(.system(size: 12))
            }
            .buttonStyle(.ttGhost)
            .help(collapsedNodeIds.isEmpty ? "Collapse All" : "Expand All")
            
            Divider().frame(height: 16)
            
            // Node count badge
            HStack(spacing: 3) {
                Circle()
                    .fill(Color.ttPrimary.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text("\(layout.nodes.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.ttTextSecondary)
                Text("nodes")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.ttTextMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ttSurface.opacity(0.92))
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.ttBorder.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Loading
    private var loadingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.ttPrimary)
            Text("Building graph layout...")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.ttSurface.opacity(0.5))
                    .frame(width: 64, height: 64)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 28))
                    .foregroundColor(.ttTextMuted)
            }
            Text("No Graph Data")
                .font(TTFont.heading3)
                .foregroundColor(.ttTextSecondary)
            Text("Enter valid JSON to visualize its structure")
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func buildLayout() async {
        isLoading = true
        let input = jsonString
        let result = await Task.detached(priority: .userInitiated) {
            JSONGraphLayoutEngine.layout(from: input)
        }.value
        
        layout = result
        isLoading = false
        restoreGraphState()
        if canvasSize != .zero {
            applyStoredViewportOrFit(size: canvasSize)
        }
    }
    
    private func fitToWindow(size: CGSize) {
        guard layout.totalSize.width > 0, layout.totalSize.height > 0 else { return }
        guard size.width > 0, size.height > 0 else { return }
        
        let padding: CGFloat = 80
        let scaleX = (size.width - padding) / layout.totalSize.width
        let scaleY = (size.height - padding) / layout.totalSize.height
        let fitScale = min(scaleX, scaleY, 1.5) // Don't scale up too much
        
        scale = max(minScale, fitScale)
        offset = CGSize(
            width: (size.width - layout.totalSize.width * scale) / 2,
            height: (size.height - layout.totalSize.height * scale) / 2
        )
    }

    private func applyStoredViewportOrFit(size: CGSize) {
        let storedScale = UserDefaults.standard.double(forKey: DefaultsKey.scale)
        if storedScale > 0 {
            scale = max(minScale, min(maxScale, storedScale))
            offset = CGSize(
                width: UserDefaults.standard.double(forKey: DefaultsKey.offsetWidth),
                height: UserDefaults.standard.double(forKey: DefaultsKey.offsetHeight)
            )
        } else {
            fitToWindow(size: size)
        }
    }

    private func restoreGraphState() {
        let validNodeIds = Set(layout.nodes.map(\.id))

        if let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.collapsedNodeIds),
           let data = rawValue.data(using: .utf8),
           let storedIds = try? JSONDecoder().decode([String].self, from: data) {
            collapsedNodeIds = Set(storedIds).intersection(validNodeIds)
        } else {
            collapsedNodeIds.removeAll()
        }

        if let storedSelectedNodeId = UserDefaults.standard.string(forKey: DefaultsKey.selectedNodeId),
           validNodeIds.contains(storedSelectedNodeId) {
            selectedNodeId = storedSelectedNodeId
        } else {
            selectedNodeId = nil
        }
    }

    private func saveViewportState() {
        UserDefaults.standard.set(Double(scale), forKey: DefaultsKey.scale)
        UserDefaults.standard.set(Double(offset.width), forKey: DefaultsKey.offsetWidth)
        UserDefaults.standard.set(Double(offset.height), forKey: DefaultsKey.offsetHeight)
    }

    private func saveGraphState() {
        let sortedIds = Array(collapsedNodeIds).sorted()
        if let data = try? JSONEncoder().encode(sortedIds),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: DefaultsKey.collapsedNodeIds)
        }

        if let selectedNodeId {
            UserDefaults.standard.set(selectedNodeId, forKey: DefaultsKey.selectedNodeId)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.selectedNodeId)
        }
    }
}
