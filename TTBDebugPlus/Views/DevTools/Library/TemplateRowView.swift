//
//  TemplateRowView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  A single row in the template list (lightweight for 10k+ scrolling).
//

import SwiftUI

struct TemplateRowView: View {
    let template: JSONTemplate
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: TTSpacing.sm) {
            Image(systemName: AppIcon.json)
                .font(.ttIcon(TTIcon.lg))
                .foregroundColor(.ttJsonKey)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TTSpacing.xxs) {
                    Text(template.name)
                        .font(TTFont.labelLarge)
                        .foregroundColor(.ttTextPrimary)
                        .lineLimit(1)
                    if template.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.ttIcon(TTIcon.xs))
                            .foregroundColor(.ttWarning)
                    }
                }

                HStack(spacing: TTSpacing.xs) {
                    if let projectName = template.project?.name {
                        Text(projectName)
                            .lineLimit(1)
                    }
                    Text(template.formattedSize)
                    if !template.tags.isEmpty {
                        Text("· \(template.tags.count) tag\(template.tags.count == 1 ? "" : "s")")
                    }
                }
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextTertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpacing.sm)
        .padding(.vertical, TTSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.sm)
                .fill(isSelected
                      ? Color.ttPrimary.opacity(0.15)
                      : (isHovered ? Color.ttSurface.opacity(0.5) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TTRadius.sm)
                .stroke(isSelected ? Color.ttPrimary.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
