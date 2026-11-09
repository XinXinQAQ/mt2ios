//
//  Sheets.swift
//  mt2ios
//
//  Dialogs: new folder / new file / rename (MT2's dialog_file_options), file
//  properties, the built-in text + hex editor, the installed-app picker and
//  the self-check panel.
//

import SwiftUI
import UIKit
import Darwin

// MARK: - Text prompt (new folder, new file, rename)

struct PromptSheet: View {
    let title: String
    let placeholder: String
    let confirmTitle: String
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $text)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        onCommit(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(190)])
    }
}

// MARK: - Properties

struct PropertiesSheet: View {
    let path: String
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [(String, String)] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows, id: \.0) { row in
                        HStack(alignment: .top) {
                            Text(row.0)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 68, alignment: .leading)
                            Text(row.1)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Section {
                    Button {
                        UIPasteboard.general.string = path
                    } label: {
                        Label("复制路径", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("属性")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { rows = SandboxFS.attributes(at: path) }
        }
    }
}

// MARK: - Editor

struct EditorSheet: View {
    let item: FSItem
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var hex = ""
    @State private var binary = false
    @State private var loaded = false
    @State private var dirty = false

    private let hexLimit = 32 * 1024

    var body: some View {
        NavigationStack {
            Group {
                if binary {
                    ScrollView([.horizontal, .vertical]) {
                        Text(hex)
                            .font(.system(size: 9, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                } else {
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: text) { _, _ in dirty = true }
                }
            }
            .overlay {
                if !loaded {
                    ProgressView()
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $binary) {
                        Image(systemName: "number")
                    }
                    .toggleStyle(.button)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(binary || !dirty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        switch SandboxFS.data(at: item.path, limit: 4 * 1024 * 1024) {
        case .failure(let error):
            onError(error.text)
            dismiss()
        case .success(let data):
            if let string = String(data: data, encoding: .utf8) {
                text = string
                binary = false
            } else {
                binary = true
                hex = EditorSheet.dump(data.prefix(hexLimit))
            }
            loaded = true
            dirty = false
        }
    }

    private func save() {
        if let error = SandboxFS.write(Data(text.utf8), to: item.path) {
            onError(error)
        } else {
            dirty = false
            dismiss()
        }
    }

    /// Classic 16-byte-per-line hex dump.
    static func dump(_ data: Data) -> String {
        var out = ""
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            let end = min(index + 16, bytes.count)
            let slice = bytes[index..<end]

            let address = String(format: "%08X", index)
            let hexPart = slice.map { String(format: "%02X", $0) }
                .enumerated()
                .map { $0.offset == 7 ? "\($0.element) " : $0.element }
                .joined(separator: " ")
            let asciiPart = slice.map { byte -> String in
                (byte >= 32 && byte < 127) ? String(UnicodeScalar(byte)) : "."
            }.joined()

            out += "\(address)  \(hexPart.padding(toLength: 49, withPad: " ", startingAt: 0))  \(asciiPart)\n"
            index = end
        }
        return out
    }
}

// MARK: - App picker

struct AppListSheet: View {
    let onPick: (AppRecord) -> Void

    @ObservedObject private var index = AppIndex.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [AppRecord] {
        let all = index.allApps()
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !index.ready {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在扫描已安装的应用…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                ForEach(filtered) { app in
                    Button {
                        onPick(app)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            icon(for: app)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                Text(app.bundleID)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索应用名或 Bundle ID")
            .navigationTitle("应用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { index.loadIfNeeded() }
        }
    }

    @ViewBuilder
    private func icon(for app: AppRecord) -> some View {
        if let bundlePath = app.bundlePath, let image = index.icon(forBundlePath: bundlePath) {
            Image(uiImage: image)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.fileBlue)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                )
        }
    }
}

// MARK: - Self check

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section("运行环境") {
                    ForEach(Array(lines.enumerated()), id: \.offset) { pair in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·").foregroundStyle(.secondary)
                            Text(pair.element)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("说明") {
                    Text("MT2iOS = MT2 的双栏界面 + worse_query 沙盒逃逸。没有越狱、没有内核利用、没有 tweak 注入；权限等同于 mobile 用户，系统卷只读。")
                        .font(.system(size: 11))
                }

                Section {
                    Button("重新自检") { lines = buildLines() }
                }
            }
            .navigationTitle("自检")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { lines = buildLines() }
        }
    }

    private func buildLines() -> [String] {
        SandboxEscape.shared.invalidateDiagnostics()
        var out = SandboxEscape.shared.diagnostics.components(separatedBy: "\n")
        out.append("已加载应用: \(AppIndex.shared.allApps().count)")
        out.append("UID: \(getuid())  EUID: \(geteuid())")
        out.append("构建: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
        return out
    }
}
