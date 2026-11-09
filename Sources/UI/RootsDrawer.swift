//
//  RootsDrawer.swift
//  mt2ios
//
//  The drawer MT2 puts behind the hamburger: shortcuts into the containers
//  that actually matter on iOS, plus user bookmarks.
//

import SwiftUI

// MARK: - Bookmarks store

final class Bookmarks: ObservableObject {
    static let shared = Bookmarks()

    @Published private(set) var paths: [String] = []
    private let key = "mt2ios.bookmarks.v1"

    private init() {
        paths = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func add(_ path: String) {
        let normalized = SandboxEscape.normalize(path)
        guard !normalized.isEmpty, !paths.contains(normalized) else { return }
        paths.append(normalized)
        persist()
    }

    func remove(_ path: String) {
        paths.removeAll { $0 == path }
        persist()
    }

    func remove(at offsets: IndexSet) {
        paths.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(paths, forKey: key)
    }
}

// MARK: - Root shortcuts

struct RootShortcut: Identifiable {
    var id: String { path }
    let path: String
    let title: String
    let symbol: String
}

enum RootShortcuts {
    static let all: [RootShortcut] = [
        RootShortcut(path: "/var/mobile/Containers/Data/Application", title: "应用数据容器", symbol: "square.stack.3d.up"),
        RootShortcut(path: "/var/containers/Bundle/Application", title: "应用安装目录", symbol: "app.badge"),
        RootShortcut(path: "/var/mobile/Containers/Shared/AppGroup", title: "App Group 共享", symbol: "square.stack.3d.down.right"),
        RootShortcut(path: "/var/mobile/Media", title: "媒体与照片", symbol: "photo.on.rectangle"),
        RootShortcut(path: "/var/mobile/Documents", title: "用户文档", symbol: "doc.text"),
        RootShortcut(path: "/var/mobile/Library", title: "用户 Library", symbol: "books.vertical"),
        RootShortcut(path: "/var/mobile", title: "mobile 主目录", symbol: "house"),
        RootShortcut(path: "/", title: "文件系统根", symbol: "externaldrive"),
        RootShortcut(path: "/var/jb", title: "rootless 越狱目录", symbol: "hammer")
    ]
}

// MARK: - Sheet

struct RootsSheet: View {
    @ObservedObject var pane: Pane
    let onShowApps: () -> Void
    let onShowAbout: () -> Void

    @ObservedObject private var bookmarks = Bookmarks.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("常用位置") {
                    ForEach(RootShortcuts.all) { shortcut in
                        Button {
                            pane.navigate(to: shortcut.path)
                            dismiss()
                        } label: {
                            Label {
                                Text(shortcut.title)
                                    .font(.system(size: 13))
                            } icon: {
                                Image(systemName: shortcut.symbol)
                                    .foregroundStyle(Theme.fileBlue)
                            }
                        }
                    }
                }

                Section("书签") {
                    if bookmarks.paths.isEmpty {
                        Text("在文件上长按 → 加入书签")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bookmarks.paths, id: \.self) { path in
                            Button {
                                pane.navigate(to: path)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text((path as NSString).lastPathComponent)
                                        .font(.system(size: 13))
                                    Text(path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) { bookmarks.remove(path) }
                            }
                        }
                    }
                }

                Section("工具") {
                    Button { onShowApps() } label: { Label("应用列表", systemImage: "square.grid.2x2") }
                    Button { onShowAbout() } label: { Label("自检 / 关于", systemImage: "stethoscope") }
                }
            }
            .navigationTitle("MT2iOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
