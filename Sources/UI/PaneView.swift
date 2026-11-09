//
//  PaneView.swift
//  mt2ios
//
//  A single MT2-style pane: thin path strip on top, 43pt rows below, the
//  scrollbar overlay on the right and the folding edge shadow that fades in as
//  you scroll. Pulling down past the top re-reads the directory.
//

import SwiftUI
import UIKit

// MARK: - Scroll plumbing

struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0        // > 0 when scrolled into content
    var contentHeight: CGFloat = 0
    var viewport: CGFloat = 0
}

struct ScrollMetricsKey: PreferenceKey {
    static var defaultValue = ScrollMetrics()
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        let next = nextValue()
        if next.contentHeight > 0 { value = next }
    }
}

struct PaneActions {
    var rename: (FSItem) -> Void = { _ in }
    var properties: (FSItem) -> Void = { _ in }
    var delete: (FSItem) -> Void = { _ in }
    var copyToOther: (FSItem) -> Void = { _ in }
    var moveToOther: (FSItem) -> Void = { _ in }
    var revealInOther: (FSItem) -> Void = { _ in }
    var bookmark: (String) -> Void = { _ in }
    var newFolder: () -> Void = {}
    var newFile: () -> Void = {}
    var jumpToPath: () -> Void = {}
}

// MARK: - Pane

struct PaneView: View {
    @ObservedObject var pane: Pane
    let isActive: Bool
    let actions: PaneActions
    let onActivate: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var metrics = ScrollMetrics()
    @State private var previousOffset: CGFloat = 0
    @State private var refreshing = false
    @State private var showPathEditor = false

    var body: some View {
        VStack(spacing: 0) {
            pathHeader
            Rectangle()
                .fill(Theme.separator(scheme))
                .frame(height: 0.5)
            content
            if let banner = pane.banner {
                bannerView(banner)
            }
        }
        .background(Theme.listBackground(scheme))
        .overlay(
            Rectangle()
                .strokeBorder(isActive ? Theme.accent.opacity(0.85) : .clear, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .simultaneousGesture(TapGesture().onEnded { onActivate() })
        .sheet(isPresented: $showPathEditor) {
            PathPrompt(initial: pane.path) { newPath in
                pane.navigate(to: newPath)
            }
        }
    }

    // MARK: Path strip

    private var pathHeader: some View {
        HStack(spacing: 6) {
            Text(pane.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.gray)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 4)

            if pane.loading {
                ProgressView().controlSize(.mini)
            }

            Button {
                showPathEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.gray)

            Button {
                pane.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.gray)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Theme.paneChrome(scheme))
    }

    // MARK: List

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if pane.items.isEmpty && !pane.loading {
                    emptyState
                } else {
                    ForEach(pane.items) { item in
                        row(for: item)
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollMetricsKey.self,
                        value: ScrollMetrics(
                            offset: -geo.frame(in: .named("paneScroll")).minY,
                            contentHeight: geo.size.height,
                            viewport: metrics.viewport
                        )
                    )
                }
            )
        }
        .coordinateSpace(name: "paneScroll")
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { metrics.viewport = geo.size.height }
                    .onChange(of: geo.size.height) { _, height in metrics.viewport = height }
            }
        )
        .onPreferenceChange(ScrollMetricsKey.self) { value in
            handleMetrics(value)
        }
        .overlay(alignment: .top) { topShadow }
        .overlay(alignment: .top) { pullIndicator }
        .overlay(alignment: .trailing) { scrollbar }
        .overlay {
            if pane.loading && pane.items.isEmpty {
                ProgressView()
            }
        }
    }

    private func row(for item: FSItem) -> some View {
        FileRow(item: item,
                selected: pane.selection.contains(item.path),
                scheme: scheme)
            .onTapGesture {
                onActivate()
                if pane.selection.isEmpty {
                    pane.activate(item)
                } else {
                    pane.toggle(item)
                }
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                onActivate()
                pane.toggle(item)
                tapHaptic()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 26)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > 36, abs(dx) > abs(dy) * 1.4 else { return }
                        onActivate()
                        pane.toggle(item)
                        tapHaptic()
                    }
            )
            .contextMenu {
                Button {
                    pane.activate(item)
                } label: {
                    Label(item.isDirectory ? "打开" : "编辑", systemImage: item.isDirectory ? "folder" : "square.and.pencil")
                }
                Button { actions.copyToOther(item) } label: { Label("复制到对面栏", systemImage: "doc.on.doc") }
                Button { actions.moveToOther(item) } label: { Label("移动到对面栏", systemImage: "arrow.right.doc.on.clipboard") }
                Button { actions.revealInOther(item) } label: { Label("在对面栏定位", systemImage: "scope") }
                Divider()
                Button { actions.rename(item) } label: { Label("重命名", systemImage: "pencil") }
                Button { actions.properties(item) } label: { Label("属性", systemImage: "info.circle") }
                Divider()
                Button { actions.bookmark(item.isDirectory ? item.path : (item.path as NSString).deletingLastPathComponent) } label: {
                    Label("加入书签", systemImage: "bookmark")
                }
                Button(role: .destructive) { actions.delete(item) } label: { Label("删除", systemImage: "trash") }
            }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundStyle(Theme.gray.opacity(0.6))
            Text(pane.banner == nil ? "空文件夹" : "无法列出目录")
                .font(.system(size: 11))
                .foregroundStyle(Theme.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Overlays

    private var topShadow: some View {
        LinearGradient(
            colors: [Color.black.opacity(shadowOpacity), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 26)
        .allowsHitTesting(false)
    }

    private var shadowOpacity: Double {
        let progress = min(1, max(0, metrics.offset / 90))
        return Double(progress) * 0.22
    }

    private var pullIndicator: some View {
        Group {
            if metrics.offset < -8 {
                let progress = min(1, -metrics.offset / 64)
                HStack(spacing: 5) {
                    Image(systemName: progress >= 1 ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 11))
                    Text(progress >= 1 ? "松开刷新" : "下拉刷新")
                        .font(.system(size: 10))
                }
                .foregroundStyle(Theme.gray)
                .padding(.top, 3)
                .opacity(Double(progress))
            }
        }
    }

    private var scrollbar: some View {
        GeometryReader { geo in
            let track = geo.size.height - 8
            if metrics.contentHeight > metrics.viewport + 1, track > 0 {
                let ratio = min(1, metrics.viewport / metrics.contentHeight)
                let thumb = max(28, track * ratio)
                let maxScroll = max(1, metrics.contentHeight - metrics.viewport)
                let progress = min(1, max(0, metrics.offset / maxScroll))
                let offsetY = 4 + progress * (track - thumb)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.gray.opacity(0.5))
                    .frame(width: 3, height: thumb)
                    .offset(y: offsetY)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func bannerView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.82))
            .onTapGesture { pane.banner = nil }
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if pane.banner == message { pane.banner = nil }
            }
    }

    // MARK: Behaviour

    private func handleMetrics(_ value: ScrollMetrics) {
        if abs(value.offset - metrics.offset) > 0.5 || abs(value.contentHeight - metrics.contentHeight) > 0.5 {
            metrics.offset = value.offset
            metrics.contentHeight = value.contentHeight
        }

        // Pulled far enough, then started springing back -> refresh.
        if previousOffset < -64 && value.offset > previousOffset, !refreshing {
            refreshing = true
            pane.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { refreshing = false }
        }
        previousOffset = value.offset
    }

    private func tapHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Path prompt

struct PathPrompt: View {
    let initial: String
    let onCommit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(initial: String, onCommit: @escaping (String) -> Void) {
        self.initial = initial
        self.onCommit = onCommit
        _text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("绝对路径") {
                    TextField("/var/mobile/...", text: $text)
                        .font(.system(size: 13, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("跳转到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("前往") {
                        onCommit(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}
