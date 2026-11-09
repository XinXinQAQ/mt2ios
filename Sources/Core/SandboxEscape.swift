//
//  SandboxEscape.swift
//  mt2ios
//
//  Swift side of worse_query: grants, caches and lifetime-manages sandbox
//  extension handles. A handle must live as long as we want to keep access to
//  that path, so handles are cached for the process lifetime and only released
//  when the app tears down.
//

import Foundation

public final class SandboxEscape {
    public static let shared = SandboxEscape()

    /// path -> extension handle
    private var handles: [String: Int64] = [:]
    private let lock = NSLock()
    private var cachedGroup: String?
    private var cachedDiagnostics: String?

    private init() {}

    // MARK: - App group

    /// The App Group this build is actually signed with. Read straight from the
    /// process entitlements, so it always matches the provisioning profile.
    public var appGroup: String {
        lock.lock()
        if let cachedGroup {
            lock.unlock()
            return cachedGroup
        }
        lock.unlock()

        let resolved = Self.groupFromEntitlements()
            ?? Self.groupFromInfoPlist()
            ?? "group.com.example.mt2ios.WQ"

        lock.lock()
        cachedGroup = resolved
        lock.unlock()
        return resolved
    }

    private static func groupFromEntitlements() -> String? {
        // SecTask 是私有 API，声明放在 Sources/Exploit/EntitlementsShim.m 里。
        guard let group = MTFirstAppGroup(), !group.isEmpty else { return nil }
        return group
    }

    private static func groupFromInfoPlist() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "WQAppGroup") as? String else { return nil }
        // Xcode leaves unexpanded build settings alone if the variable is empty.
        if raw.isEmpty || raw.hasPrefix("$(") || raw.contains("example") { return nil }
        return raw
    }

    // MARK: - Access

    /// True when the path, or one of its ancestors, already has an extension.
    public func hasAccess(to path: String) -> Bool {
        let p = Self.normalize(path)
        lock.lock()
        defer { lock.unlock() }
        for key in handles.keys {
            if p == key { return true }
            let prefix = key.hasSuffix("/") ? key : key + "/"
            if p.hasPrefix(prefix) { return true }
        }
        return false
    }

    /// Grants access if needed. Returns nil on success, or a human readable
    /// error on failure.
    @discardableResult
    public func ensureAccess(to path: String) -> String? {
        let p = Self.normalize(path)
        if hasAccess(to: p) { return nil }
        return grant(p)
    }

    private func grant(_ path: String) -> String? {
        // iOS 26 AppGroup containers answer a subtly different query.
        let alt = path.contains("/var/mobile/Containers/Shared/AppGroup")
            && ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26

        // First try with the existence pre-check. If our own lstat is blocked by
        // the sandbox (metadata reads are not guaranteed outside the container),
        // the primitive answers -255 even though the path is perfectly fine, so
        // retry and let containermanagerd resolve it instead.
        var handle = worse_query(path, appGroup, alt, false)
        if handle == -255 {
            handle = worse_query(path, appGroup, alt, true)
        }
        guard handle >= 0 else {
            return Self.describe(handle: handle)
        }

        // A token can come back while the sandbox still refuses us; verify with
        // a real filesystem call instead of trusting the handle.
        let readable = FileManager.default.isReadableFile(atPath: path)
        if !readable {
            worse_query_release(handle)
            return "扩展已下发，但沙盒仍拒绝访问（token 无效）\n如果是首次运行，请确认签名带 App Groups"
        }

        lock.lock()
        handles[path] = handle
        lock.unlock()
        return nil
    }

    /// Release everything. Only call on teardown.
    public func releaseAll() {
        lock.lock()
        let all = handles
        handles.removeAll()
        lock.unlock()
        for (_, handle) in all { worse_query_release(handle) }
    }

    // MARK: - Diagnostics

    public var diagnostics: String {
        lock.lock()
        if let cachedDiagnostics {
            lock.unlock()
            return cachedDiagnostics
        }
        lock.unlock()

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        let text = """
        iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        App Group: \(appGroup)
        容器可用: \(root != nil ? "是" : "否（签名没带 App Groups，逃逸不可用）")
        已持有扩展: \(handles.count)
        """

        lock.lock()
        cachedDiagnostics = text
        lock.unlock()
        return text
    }

    public func invalidateDiagnostics() {
        lock.lock()
        cachedDiagnostics = nil
        lock.unlock()
    }

    /// 现场跑一次探针，把原始返回码打出来 —— 排查“打不开”比猜有用得多。
    public func selfTest() -> [String] {
        var out: [String] = []
        let groupRoot = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        out.append("group 容器: \(groupRoot?.path ?? "nil")")

        if let groupRoot {
            let library = groupRoot.appendingPathComponent("Library").path
            out.append("Library 可写: \(FileManager.default.isWritableFile(atPath: library))")
        }

        for probe in ["/var/mobile/Media", "/var/mobile/Library"] {
            let handle = worse_query(probe, appGroup, false, false)
            guard handle >= 0 else {
                out.append("探针 \(probe) -> \(handle)：\(Self.describe(handle: handle))")
                continue
            }

            let readable = FileManager.default.isReadableFile(atPath: probe)
            let readdirCount = (try? FileManager.default.contentsOfDirectory(atPath: probe).count) ?? -1

            var scanCount = -1
            if readdirCount < 0 {
                probe.withCString { cPath in
                    guard let raw = mt2_list_paths(cPath, min(SandboxFS.scanMaxInode, 200_000)) else { return }
                    defer { free(raw) }
                    scanCount = String(cString: raw).split(separator: "\n").count
                }
            }

            out.append("探针 \(probe) -> handle \(handle) | 可读:\(readable) readdir:\(readdirCount) inode扫描:\(scanCount)")
            worse_query_release(handle)
        }
        return out
    }

    // MARK: - Helpers

    public static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        if p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p.isEmpty ? "/" : p
    }

    private static func describe(handle: Int64) -> String {
        switch handle {
        case -1:  return "拿不到 App Group 容器（签名缺少 com.apple.security.application-groups）"
        case -2:  return "系统库符号解析失败（iOS 版本不受支持）"
        case -3:  return "container_query 创建失败"
        case -4:  return "无法替换 Library/Caches 软链接"
        case -5:  return "containermanagerd 拒绝了查询（路径受保护或已被修复）"
        case -6:  return "内核拒绝下发沙盒扩展"
        case -255: return "目标路径不存在"
        default:  return "未知错误 \(handle)"
        }
    }
}
