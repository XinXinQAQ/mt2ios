//
//  SandboxFS.swift
//  mt2ios
//
//  Every filesystem call funnels through here so that access is granted
//  exactly once per path tree, and every failure comes back as a string the UI
//  can show in a toast instead of a crash.
//

import Foundation
import Darwin

/// Failure payload that can go straight into a toast.
public struct FSMessage: Error, ExpressibleByStringLiteral, CustomStringConvertible {
    public let text: String
    public init(stringLiteral value: String) { self.text = value }
    public init(_ text: String) { self.text = text }
    public var description: String { text }
}

public typealias FSResult<T> = Result<T, FSMessage>

public enum SandboxFS {
    private static var fm: FileManager { .default }

    // MARK: - 目录枚举
    //
    // 两条路：
    //   1. readdir —— 快，但只有拿到该目录 sandbox extension 之后才被允许；
    //   2. fsgetpath(inode) 扫描 —— 慢，但不需要目录读权限。
    //
    // 容器根（/var/mobile/Containers/Data/Application）这类位置，扩展只能拿到
    // “某个具体容器”，拿不到父目录，所以第 1 条会失败，必须落到第 2 条。

    /// inode 扫描上限。越大越全、越慢。可在 UserDefaults 里用 mt2.maxInode 覆盖。
    public static var scanMaxInode: Int64 {
        let stored = UserDefaults.standard.object(forKey: "mt2.maxInode") as? NSNumber
        let value = stored?.int64Value ?? 2_000_000
        return max(100_000, value)
    }

    public struct DirListing {
        public var paths: [String]
        public var fromReaddir: Bool
    }

    private static var listingCache: [String: (listing: DirListing, at: Date)] = [:]
    private static let cacheLock = NSLock()
    private static let cacheTTL: TimeInterval = 25

    /// 列出目录的直接子项（完整路径）。两条路都失败时返回 nil。
    public static func listing(of dir: String, useCache: Bool = true) -> DirListing? {
        let path = SandboxEscape.normalize(dir)

        if useCache {
            cacheLock.lock()
            if let cached = listingCache[path], Date().timeIntervalSince(cached.at) < cacheTTL {
                cacheLock.unlock()
                return cached.listing
            }
            cacheLock.unlock()
        }

        var result: DirListing?

        if let names = try? fm.contentsOfDirectory(atPath: path) {
            result = DirListing(paths: names.map { (path as NSString).appendingPathComponent($0) },
                                fromReaddir: true)
        } else {
            let scanned: [String] = path.withCString { cPath in
                guard let raw = mt2_list_paths(cPath, scanMaxInode) else { return [] }
                defer { free(raw) }
                let text = String(cString: raw)
                guard !text.isEmpty else { return [] }
                return text.split(separator: "\n").map(String.init)
            }
            if !scanned.isEmpty {
                result = DirListing(paths: scanned, fromReaddir: false)
            }
        }

        if let result {
            cacheLock.lock()
            listingCache[path] = (result, Date())
            cacheLock.unlock()
        }
        return result
    }

    public static func invalidateListing(for dir: String? = nil) {
        cacheLock.lock()
        if let dir {
            listingCache.removeValue(forKey: SandboxEscape.normalize(dir))
        } else {
            listingCache.removeAll()
        }
        cacheLock.unlock()
    }

    // MARK: - Reading

    public static func entries(in dir: String,
                               includeHidden: Bool,
                               sort: SortMode) -> FSResult<[FSItem]> {
        let path = SandboxEscape.normalize(dir)

        // 授权失败不算致命：列表可能靠 inode 扫描照样出来，只是读写会失败。
        let grantError = SandboxEscape.shared.ensureAccess(to: path)

        guard let listing = listing(of: path) else {
            let hint = grantError ?? "readdir 被拒绝，inode 扫描也没有结果"
            return .failure(FSMessage("无法读取目录\n\(hint)\n\(path)"))
        }

        var items: [FSItem] = []
        items.reserveCapacity(listing.paths.count)
        for child in listing.paths {
            let name = (child as NSString).lastPathComponent
            if !includeHidden && name.hasPrefix(".") { continue }
            items.append(FSItem(path: child))
        }
        return .success(sorted(items, by: sort))
    }

    public static func sorted(_ items: [FSItem], by mode: SortMode) -> [FSItem] {
        func nameKey(_ i: FSItem) -> String { i.name.lowercased() }
        let directoriesFirst: (FSItem, FSItem) -> Bool? = { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return nil
        }
        return items.sorted { a, b in
            if let forced = directoriesFirst(a, b) { return forced }
            switch mode {
            case .nameAsc:  return nameKey(a) < nameKey(b)
            case .nameDesc: return nameKey(a) > nameKey(b)
            case .dateDesc: return a.modified > b.modified
            case .dateAsc:  return a.modified < b.modified
            case .sizeDesc: return a.size > b.size
            case .sizeAsc:  return a.size < b.size
            case .kindAsc:
                if a.extensionName != b.extensionName { return a.extensionName < b.extensionName }
                return nameKey(a) < nameKey(b)
            }
        }
    }

    /// "12.4 GB / 128 GB" style summary for the title bar, MT2 shows this under
    /// the path.
    public static func storageSummary(for path: String) -> String {
        var s = statfs()
        let target = SandboxEscape.normalize(path)
        guard statfs(target, &s) == 0 else { return "" }
        let blockSize = Int64(s.f_bsize)
        let total = Int64(s.f_blocks) * blockSize
        let free = Int64(s.f_bavail) * blockSize
        let used = max(0, total - free)
        let percent = total > 0 ? Int(Double(used) / Double(total) * 100) : 0
        return "可用 \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) / 共 \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) · \(percent)% 已用"
    }

    public static func text(at path: String, limit: Int = 2_000_000) -> FSResult<String> {
        switch data(at: path, limit: limit) {
        case .failure(let e): return .failure(e)
        case .success(let d):
            if let s = String(data: d, encoding: .utf8) { return .success(s) }
            if let s = String(data: d, encoding: .isoLatin1) { return .success(s) }
            return .failure("不是可解码的文本文件（试试十六进制视图）")
        }
    }

    public static func data(at path: String, limit: Int = 2_000_000) -> FSResult<Data> {
        if let error = SandboxEscape.shared.ensureAccess(to: path) { return .failure(FSMessage(error)) }
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return .failure(FSMessage("打不开文件\n\(path)"))
        }
        defer { try? handle.close() }
        do {
            let d = try handle.read(upToCount: limit) ?? Data()
            return .success(d)
        } catch {
            return .failure(FSMessage(error.localizedDescription))
        }
    }

    public static func attributes(at path: String) -> [(String, String)] {
        var rows: [(String, String)] = []
        var st = stat()
        guard lstat(path, &st) == 0 else { return [("错误", "lstat 失败")] }

        let item = FSItem(path: path)
        rows.append(("路径", path))
        rows.append(("名称", item.name))
        rows.append(("类型", typeDescription(item)))
        rows.append(("大小", item.sizeText))
        rows.append(("权限", "\(item.typeChar)\(item.permissionText)  (\(String(format: "%o", item.mode & 0o7777)))"))
        rows.append(("属主", ownerName(uid: st.st_uid, gid: st.st_gid)))
        rows.append(("inode", "\(st.st_ino)"))
        rows.append(("硬链接数", "\(st.st_nlink)"))
        rows.append(("修改时间", fullDate(item.modified)))
        if item.isSymlink, let dest = try? fm.destinationOfSymbolicLink(atPath: path) {
            rows.append(("链接目标", dest))
        }
        if item.isDirectory {
            let count = (try? fm.contentsOfDirectory(atPath: path).count) ?? 0
            rows.append(("条目数", "\(count)"))
        }
        return rows
    }

    // MARK: - Writing

    public static func write(_ data: Data, to path: String) -> String? {
        if let error = SandboxEscape.shared.ensureAccess(to: (path as NSString).deletingLastPathComponent) {
            return error
        }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            invalidateListing()
            return nil
        } catch {
            // .atomic writes a temp file next to the target; some system dirs
            // block that, fall back to an in-place write.
            do {
                try data.write(to: URL(fileURLWithPath: path))
                invalidateListing()
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    public static func createFolder(in dir: String, name: String) -> String? {
        if let error = SandboxEscape.shared.ensureAccess(to: dir) { return error }
        let target = (dir as NSString).appendingPathComponent(name)
        do {
            try fm.createDirectory(atPath: target, withIntermediateDirectories: false)
            invalidateListing()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func createFile(in dir: String, name: String, data: Data = Data()) -> String? {
        if let error = SandboxEscape.shared.ensureAccess(to: dir) { return error }
        let target = (dir as NSString).appendingPathComponent(name)
        if fm.fileExists(atPath: target) { return "同名文件已存在" }
        guard fm.createFile(atPath: target, contents: data) else { return "创建失败" }
        invalidateListing()
        return nil
    }

    public static func copy(_ src: String, toDir dir: String) -> String? {
        if let error = SandboxEscape.shared.ensureAccess(to: src) { return error }
        if let error = SandboxEscape.shared.ensureAccess(to: dir) { return error }
        let dst = uniqueDestination(for: src, in: dir)
        do {
            try fm.copyItem(atPath: src, toPath: dst)
            invalidateListing()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func move(_ src: String, toDir dir: String) -> String? {
        if let error = SandboxEscape.shared.ensureAccess(to: src) { return error }
        if let error = SandboxEscape.shared.ensureAccess(to: dir) { return error }
        let dst = uniqueDestination(for: src, in: dir)
        do {
            // rename(2) keeps metadata and is atomic when both paths share a volume.
            if Darwin.rename(src, dst) == 0 {
                invalidateListing()
                return nil
            }
            try fm.moveItem(atPath: src, toPath: dst)
            invalidateListing()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func rename(_ src: String, to newName: String) -> String? {
        let parent = (src as NSString).deletingLastPathComponent
        if let error = SandboxEscape.shared.ensureAccess(to: parent) { return error }
        let dst = (parent as NSString).appendingPathComponent(newName)
        if fm.fileExists(atPath: dst) { return "目标已存在" }
        do {
            try fm.moveItem(atPath: src, toPath: dst)
            invalidateListing()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func delete(_ path: String) -> String? {
        if let error = SandboxEscape.shared.ensureAccess(to: path) { return error }
        do {
            try fm.removeItem(atPath: path)
            invalidateListing()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func chmod(_ path: String, mode: mode_t) -> String? {
        if let error = SandboxEscape.shared.ensureAccess(to: path) { return error }
        return Darwin.chmod(path, mode) == 0 ? nil : String(cString: strerror(errno))
    }

    public static func setModificationDate(_ path: String, to date: Date) -> String? {
        if let error = SandboxEscape.shared.ensureAccess(to: path) { return error }
        do {
            var url = URL(fileURLWithPath: path)
            var values = URLResourceValues()
            values.contentModificationDate = date
            try url.setResourceValues(values)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Path helpers

    public static func parent(of path: String) -> String? {
        let p = SandboxEscape.normalize(path)
        guard p != "/" else { return nil }
        let parent = (p as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    public static func join(_ dir: String, _ name: String) -> String {
        (SandboxEscape.normalize(dir) as NSString).appendingPathComponent(name)
    }

    private static func uniqueDestination(for src: String, in dir: String) -> String {
        let name = (src as NSString).lastPathComponent
        var candidate = (dir as NSString).appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while true {
            let next = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = (dir as NSString).appendingPathComponent(next)
            if !fm.fileExists(atPath: candidate) { return candidate }
            index += 1
        }
    }

    private static func typeDescription(_ item: FSItem) -> String {
        if item.isSymlink { return "符号链接" }
        if item.isDirectory { return "文件夹" }
        if item.extensionName.isEmpty { return "文件" }
        return "\(item.extensionName.uppercased()) 文件"
    }

    private static func ownerName(uid: uid_t, gid: gid_t) -> String {
        let user = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? "?"
        let group = getgrgid(gid).map { String(cString: $0.pointee.gr_name) } ?? "?"
        return "\(user):\(group) (\(uid):\(gid))"
    }

    private static func fullDate(_ date: Date) -> String {
        if date.timeIntervalSince1970 == 0 { return "--" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}
