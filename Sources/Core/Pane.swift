//
//  Pane.swift
//  mt2ios
//
//  One half of the dual-pane view: current path, history stack, selection,
//  sort order and the error banner. MT2 keeps two independent panes on screen
//  at once and so do we.
//

import Foundation
import Combine

public final class Pane: ObservableObject, Identifiable {
    public let id = UUID()

    @Published public private(set) var path: String
    @Published public var items: [FSItem] = []
    @Published public var selection: Set<String> = []
    @Published public var sort: SortMode = .nameAsc {
        didSet { items = SandboxFS.sorted(items, by: sort) }
    }
    @Published public var showHidden = false {
        didSet { reload() }
    }
    @Published public var loading = false
    @Published public var banner: String?
    @Published public var editing: FSItem?
    @Published public private(set) var storageText = ""

    private var backStack: [String] = []
    private var forwardStack: [String] = []
    private var loadToken = UUID()

    public init(path: String) {
        self.path = SandboxEscape.normalize(path)
    }

    // MARK: - Derived state

    public var selectionItems: [FSItem] {
        items.filter { selection.contains($0.path) }
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
    public var canGoUp: Bool { path != "/" }

    public var title: String {
        path == "/" ? "/" : (path as NSString).lastPathComponent
    }

    // MARK: - Loading

    public func reload() {
        let target = path
        let hidden = showHidden
        let order = sort
        let token = UUID()
        loadToken = token
        loading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = SandboxFS.entries(in: target, includeHidden: hidden, sort: order)
            let storage = SandboxFS.storageSummary(for: target)
            DispatchQueue.main.async {
                guard let self, self.loadToken == token else { return }
                self.loading = false
                self.storageText = storage
                switch result {
                case .success(let list):
                    self.items = list
                    self.selection = self.selection.intersection(Set(list.map(\.path)))
                case .failure(let message):
                    self.items = []
                    self.banner = message.text
                }
            }
        }
    }

    // MARK: - Navigation

    public func navigate(to newPath: String, pushHistory: Bool = true) {
        let target = SandboxEscape.normalize(newPath)
        guard target != path else {
            reload()
            return
        }
        if pushHistory {
            backStack.append(path)
            forwardStack.removeAll()
        }
        path = target
        selection.removeAll()
        reload()
    }

    public func activate(_ item: FSItem) {
        if item.isDirectory {
            navigate(to: item.path)
        } else {
            editing = item
        }
    }

    public func goUp() {
        guard let parent = SandboxFS.parent(of: path) else { return }
        navigate(to: parent)
    }

    public func back() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(path)
        path = previous
        selection.removeAll()
        reload()
    }

    public func forward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(path)
        path = next
        selection.removeAll()
        reload()
    }

    /// Jump without touching the history, used by bookmarks and "reveal in
    /// other pane".
    public func reset(to newPath: String) {
        path = SandboxEscape.normalize(newPath)
        backStack.removeAll()
        forwardStack.removeAll()
        selection.removeAll()
        reload()
    }

    // MARK: - Selection

    public func toggle(_ item: FSItem) {
        if selection.contains(item.path) {
            selection.remove(item.path)
        } else {
            selection.insert(item.path)
        }
    }

    public func selectAll() {
        selection = Set(items.map(\.path))
    }

    public func clearSelection() {
        selection.removeAll()
    }

    // MARK: - Feedback

    public func show(_ message: String) {
        banner = message
    }

    public func showFileOperationError(_ error: String?) {
        guard let error, !error.isEmpty else { return }
        banner = error
    }
}
