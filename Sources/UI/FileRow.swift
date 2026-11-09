//
//  FileRow.swift
//  mt2ios
//
//  One list row, 43pt tall: 28pt rounded glyph frame, name on top, muted
//  second line (app name · date · size), app icon badge in the corner for
//  container folders — same hierarchy as MT2's item_file.xml.
//

import SwiftUI

struct FileRow: View {
    let item: FSItem
    let selected: Bool
    let scheme: ColorScheme

    @ObservedObject private var index = AppIndex.shared

    private var appRecord: AppRecord? {
        index.record(forDataPath: item.path)
    }

    private var appIcon: UIImage? {
        guard item.isDirectory else { return nil }
        return index.icon(forDataPath: item.path)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let appRecord {
            parts.append(appRecord.name)
        } else {
            parts.append(item.dateText)
        }
        if !item.isDirectory {
            parts.append(item.sizeText)
        }
        if item.isSymlink {
            parts.append("链接")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(item.tint)
                    .frame(width: Theme.iconFrame, height: Theme.iconFrame)

                Image(systemName: item.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: Theme.iconFrame, height: Theme.iconFrame)

                if let appIcon {
                    Image(uiImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color.white, lineWidth: 0.5)
                        )
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: Theme.iconFrame + 2, height: Theme.iconFrame + 2, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.rowHeight)
        .background(selected ? Theme.selectionFill(scheme) : Color.clear)
        .contentShape(Rectangle())
    }
}
