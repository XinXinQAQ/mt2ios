//
//  ActionBar.swift
//  mt2ios
//
//  The bottom bar from MT2's activity_main.xml, rebuilt: back / forward /
//  new / transfer-to-other-pane / up when nothing is selected, and a selection
//  bar (copy, move, delete, rename) once rows are picked.
//

import SwiftUI

struct ActionBarActions {
    var newFolder: () -> Void
    var newFile: () -> Void
    var copyToOther: () -> Void
    var moveToOther: () -> Void
    var deleteSelection: () -> Void
    var renameSelection: () -> Void
    var propertiesSelection: () -> Void
    var selectAll: () -> Void
    var clearSelection: () -> Void
}

struct ActionBar: View {
    @ObservedObject var pane: Pane
    @ObservedObject var other: Pane
    let scheme: ColorScheme
    let actions: ActionBarActions

    var body: some View {
        HStack(spacing: 0) {
            if pane.selection.isEmpty {
                navigationBar
            } else {
                selectionBar
            }
        }
        .frame(height: Theme.actionBarHeight)
        .background(Theme.paneChrome(scheme))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.separator(scheme))
                .frame(height: 0.5)
        }
    }

    // MARK: - Normal mode

    private var navigationBar: some View {
        HStack(spacing: 0) {
            barButton("chevron.left", enabled: pane.canGoBack) { pane.back() }
            barButton("chevron.right", enabled: pane.canGoForward) { pane.forward() }

            Menu {
                Button { actions.newFolder() } label: { Label("新建文件夹", systemImage: "folder.badge.plus") }
                Button { actions.newFile() } label: { Label("新建文件", systemImage: "doc.badge.plus") }
                Divider()
                Button { actions.selectAll() } label: { Label("全选", systemImage: "checkmark.circle") }
                Button { pane.showHidden.toggle() } label: {
                    Label(pane.showHidden ? "隐藏隐藏文件" : "显示隐藏文件", systemImage: "eye")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Theme.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }

            Menu {
                Button { actions.copyToOther() } label: { Label("复制到对面栏", systemImage: "doc.on.doc") }
                Button { actions.moveToOther() } label: { Label("移动到对面栏", systemImage: "arrow.right.doc.on.clipboard") }
                Divider()
                Text(other.path)
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }

            barButton("arrow.up", enabled: pane.canGoUp) { pane.goUp() }
        }
    }

    // MARK: - Selection mode

    private var selectionBar: some View {
        HStack(spacing: 0) {
            Text("已选 \(pane.selection.count)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.gray)
                .padding(.horizontal, 10)

            Spacer(minLength: 0)

            selectionButton("doc.on.doc", "复制") { actions.copyToOther() }
            selectionButton("arrow.right.doc.on.clipboard", "移动") { actions.moveToOther() }
            selectionButton("pencil", "重命名") { actions.renameSelection() }
            selectionButton("info.circle", "属性") { actions.propertiesSelection() }
            selectionButton("trash", "删除", tint: .red) { actions.deleteSelection() }
            selectionButton("xmark", "取消") { actions.clearSelection() }
        }
    }

    // MARK: - Pieces

    private func barButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(enabled ? Theme.gray : Theme.gray.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }

    private func selectionButton(_ symbol: String, _ title: String,
                                 tint: Color = Theme.gray,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.system(size: 9))
            }
            .foregroundStyle(tint)
            .frame(width: 48, height: Theme.actionBarHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
