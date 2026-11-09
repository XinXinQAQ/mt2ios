//
//  RootView.swift
//  mt2ios
//
//  Dual-pane shell: 56pt toolbar (path + free space + overflow menu), two
//  independent panes with a draggable splitter, 50pt bottom action bar.
//  Mirrors MT2's activity_main.xml, minus the Android-only bits.
//

import SwiftUI

// MARK: - Sheet payloads

struct PathBox: Identifiable {
    let path: String
    var id: String { path }
}

enum PromptTarget: Identifiable {
    case newFolder(Pane)
    case newFile(Pane)
    case rename(Pane, FSItem)

    var id: String {
        switch self {
        case .newFolder(let pane): return "nf-\(pane.id)-\(pane.path)"
        case .newFile(let pane):   return "nf2-\(pane.id)-\(pane.path)"
        case .rename(_, let item): return "rn-\(item.path)"
        }
    }
}

// MARK: - Root

struct RootView: View {
    @StateObject private var left = Pane(path: "/var/mobile/Containers/Data/Application")
    @StateObject private var right = Pane(path: "/var/mobile/Media")

    @Environment(\.colorScheme) private var scheme

    @State private var ratio: CGFloat = 0.5
    @State private var activeIsLeft = true

    @State private var showRoots = false
    @State private var showApps = false
    @State private var showAbout = false

    @State private var propertiesItem: PathBox?
    @State private var prompt: PromptTarget?
    @State private var pendingDelete: [FSItem] = []
    @State private var pendingDeletePane: Pane?
    @State private var showDeleteConfirm = false

    private var active: Pane { activeIsLeft ? left : right }
    private var inactive: Pane { activeIsLeft ? right : left }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                titleBar

                HStack(spacing: 0) {
                    PaneView(pane: left,
                             isActive: activeIsLeft,
                             actions: paneActions(for: left, other: right),
                             onActivate: { activeIsLeft = true })
                        .frame(width: leftWidth(in: geo.size.width))

                    Splitter(ratio: $ratio, containerWidth: geo.size.width, scheme: scheme)

                    PaneView(pane: right,
                             isActive: !activeIsLeft,
                             actions: paneActions(for: right, other: left),
                             onActivate: { activeIsLeft = false })
                        .frame(maxWidth: .infinity)
                }

                ActionBar(pane: active, other: inactive, scheme: scheme, actions: barActions)
            }
        }
        .background(Theme.listBackground(scheme))
        .onAppear(perform: bootstrap)
        // Sheets
        .sheet(isPresented: $showRoots) {
            RootsSheet(pane: active,
                       onShowApps: { showRoots = false; showApps = true },
                       onShowAbout: { showRoots = false; showAbout = true })
        }
        .sheet(isPresented: $showApps) {
            AppListSheet { app in
                if let container = app.dataContainer {
                    active.navigate(to: container)
                }
            }
        }
        .sheet(isPresented: $showAbout) { AboutSheet() }
        .sheet(item: $propertiesItem) { box in
            PropertiesSheet(path: box.path)
        }
        .sheet(item: $prompt) { target in
            promptSheet(for: target)
        }
        .sheet(item: $left.editing) { item in
            EditorSheet(item: item) { left.show($0) }
        }
        .sheet(item: $right.editing) { item in
            EditorSheet(item: item) { right.show($0) }
        }
        .confirmationDialog(deleteTitle, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { performDelete() }
            Button("取消", role: .cancel) { pendingDelete = []; pendingDeletePane = nil }
        }
    }

    // MARK: - Layout

    private func leftWidth(in total: CGFloat) -> CGFloat {
        max(120, (total - 10) * ratio)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Button {
                showRoots = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 26, height: 26)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(active.path)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(active.storageText)
                    .font(.system(size: 10))
                    .opacity(0.65)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Menu {
                moreMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 26, height: 26)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(Theme.toolbar.ignoresSafeArea(edges: .top))
    }

    @ViewBuilder
    private var moreMenu: some View {
        Button { showApps = true } label: { Label("应用列表", systemImage: "square.grid.2x2") }
        Button { showAbout = true } label: { Label("自检", systemImage: "stethoscope") }
        Divider()
        Menu {
            ForEach(SortMode.allCases) { mode in
                Button {
                    active.sort = mode
                } label: {
                    if active.sort == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            Label("排序：\(active.sort.title)", systemImage: "arrow.up.arrow.down")
        }
        Toggle(isOn: Binding(get: { active.showHidden }, set: { active.showHidden = $0 })) {
            Label("显示隐藏文件", systemImage: "eye")
        }
        Divider()
        Button { active.selectAll() } label: { Label("全选", systemImage: "checkmark.circle") }
        Button { active.clearSelection() } label: { Label("取消选择", systemImage: "circle.dashed") }
        Divider()
        Button { active.reset(to: "/") } label: { Label("回到根目录", systemImage: "arrow.uturn.backward") }
        Button { left.reload(); right.reload() } label: { Label("刷新两栏", systemImage: "arrow.clockwise") }
    }

    // MARK: - Actions

    private func paneActions(for pane: Pane, other: Pane) -> PaneActions {
        PaneActions(
            rename: { item in prompt = .rename(pane, item) },
            properties: { item in propertiesItem = PathBox(path: item.path) },
            delete: { item in requestDelete(pane, [item]) },
            copyToOther: { item in transfer([item], from: pane, to: other, move: false) },
            moveToOther: { item in transfer([item], from: pane, to: other, move: true) },
            revealInOther: { item in
                let target = item.isDirectory ? item.path : (item.path as NSString).deletingLastPathComponent
                other.reset(to: target)
            },
            bookmark: { path in Bookmarks.shared.add(path) },
            newFolder: { prompt = .newFolder(pane) },
            newFile: { prompt = .newFile(pane) },
            jumpToPath: { pane.reload() }
        )
    }

    private var barActions: ActionBarActions {
        ActionBarActions(
            newFolder: { prompt = .newFolder(active) },
            newFile: { prompt = .newFile(active) },
            copyToOther: { transfer(active.selectionItems, from: active, to: inactive, move: false) },
            moveToOther: { transfer(active.selectionItems, from: active, to: inactive, move: true) },
            deleteSelection: { requestDelete(active, active.selectionItems) },
            renameSelection: {
                if let item = active.selectionItems.first { prompt = .rename(active, item) }
            },
            propertiesSelection: {
                if let item = active.selectionItems.first { propertiesItem = PathBox(path: item.path) }
            },
            selectAll: { active.selectAll() },
            clearSelection: { active.clearSelection() }
        )
    }

    private func transfer(_ items: [FSItem], from source: Pane, to destination: Pane, move: Bool) {
        guard !items.isEmpty else {
            source.show("先选中文件")
            return
        }
        guard SandboxEscape.normalize(source.path) != SandboxEscape.normalize(destination.path) else {
            source.show("目标就是当前目录")
            return
        }

        var errors: [String] = []
        for item in items {
            let error = move
                ? SandboxFS.move(item.path, toDir: destination.path)
                : SandboxFS.copy(item.path, toDir: destination.path)
            if let error {
                errors.append("\(item.name)：\(error)")
            }
        }

        source.clearSelection()
        source.reload()
        destination.reload()
        if !errors.isEmpty {
            source.show(errors.joined(separator: "\n"))
        }
    }

    private var deleteTitle: String {
        pendingDelete.count > 1 ? "删除 \(pendingDelete.count) 项？此操作不可撤销" : "删除 \(pendingDelete.first?.name ?? "")？此操作不可撤销"
    }

    private func requestDelete(_ pane: Pane, _ items: [FSItem]) {
        guard !items.isEmpty else { return }
        pendingDeletePane = pane
        pendingDelete = items
        showDeleteConfirm = true
    }

    private func performDelete() {
        let items = pendingDelete
        guard let pane = pendingDeletePane else {
            pendingDelete = []
            return
        }
        pendingDelete = []
        pendingDeletePane = nil

        var errors: [String] = []
        for item in items {
            if let error = SandboxFS.delete(item.path) {
                errors.append("\(item.name)：\(error)")
            }
        }
        pane.clearSelection()
        pane.reload()
        if !errors.isEmpty { pane.show(errors.joined(separator: "\n")) }
    }

    @ViewBuilder
    private func promptSheet(for target: PromptTarget) -> some View {
        switch target {
        case .newFolder(let pane):
            PromptSheet(title: "新建文件夹", placeholder: "文件夹名", confirmTitle: "创建") { name in
                if let error = SandboxFS.createFolder(in: pane.path, name: name) {
                    pane.show(error)
                }
                pane.reload()
            }
        case .newFile(let pane):
            PromptSheet(title: "新建文件", placeholder: "文件名.txt", confirmTitle: "创建") { name in
                if let error = SandboxFS.createFile(in: pane.path, name: name) {
                    pane.show(error)
                }
                pane.reload()
            }
        case .rename(let pane, let item):
            PromptSheet(title: "重命名", placeholder: item.name, confirmTitle: "确定") { name in
                if let error = SandboxFS.rename(item.path, to: name) {
                    pane.show(error)
                }
                pane.reload()
            }
        }
    }

    // MARK: - Startup

    private func bootstrap() {
        left.reload()
        right.reload()
        AppIndex.shared.loadIfNeeded()

        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SandboxEscape.shared.appGroup) == nil {
            left.show("""
            签名里没有 App Groups，沙盒逃逸不可用。
            当前 group: \(SandboxEscape.shared.appGroup)
            用带 App Groups 能力的描述文件重新签名后再试。
            """)
        }
    }
}

// MARK: - Splitter

struct Splitter: View {
    @Binding var ratio: CGFloat
    let containerWidth: CGFloat
    let scheme: ColorScheme

    @State private var startRatio: CGFloat?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Theme.separator(scheme))
                .frame(width: 0.5)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.gray.opacity(0.6))
                .frame(width: 6, height: 44)
        }
        .frame(width: 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let base = startRatio ?? ratio
                    if startRatio == nil { startRatio = base }
                    let usable = max(1, containerWidth - 10)
                    let next = base + value.translation.width / usable
                    ratio = min(0.8, max(0.2, next))
                }
                .onEnded { _ in startRatio = nil }
        )
    }
}
