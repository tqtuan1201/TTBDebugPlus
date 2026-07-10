//
//  MenuBarDeviceRow.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Compact device row for menu bar dropdown
//

import SwiftUI

struct MenuBarDeviceRow: View {
    @Environment(ConnectionManager.self) private var connectionManager
    let session: DeviceSession
    
    @State private var isHovered = false

    private var online: Bool { session.isOnline(relativeTo: connectionManager.uiNow) }
    private var warning: Bool { session.isHeartbeatWarning(relativeTo: connectionManager.uiNow) }
    
    var body: some View {
        HStack(spacing: 8) {
            // Device icon
            Image(systemName: session.isSimulator ? AppIcon.simulator : AppIcon.device)
                .font(.system(size: 11))
                .foregroundColor(online ? .ttSuccess : .ttTextMuted)
                .frame(width: 16)
            
            // Device info
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Text(session.osVersionString)
                    .font(.system(size: 10))
                    .foregroundColor(.ttTextSecondary)
            }
            
            Spacer()
            
            // Status dot: green / amber / offline
            Circle()
                .fill(online ? (warning ? Color.ttWarning : Color.ttSuccess) : Color.ttTextMuted.opacity(0.5))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.ttSurfaceHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
