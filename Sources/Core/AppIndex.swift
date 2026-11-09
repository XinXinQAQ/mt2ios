//
//  AppIndex.swift
//  mt2ios
//
//  Maps a data container path back to the app that owns it, so the file list
//  can show "微信" instead of "0A1B2C3D-..." the way MT2 does.
//
//  Everything here is read through the same sandbox extension as the rest of
//  the file manager: /var/containers/Bundle/Application for names and icons,
//  /var/mobile/Containers/Data/Application/<uuid>/​.com.apple.mobile_container_manager.metadata.plist
//  for the container -> bundle id link.
//

import Foundation
import UIKit

public struct AppRecord: Identifiable, Hashable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let bundlePath: String?
    public let dataContainer: String?
}

public final class AppIndex: ObservableObject {
    public static let shared = AppIndex()

    @Published public private(set) var ready = false

    private var byBundleID: [String: AppRecord] = [:]
    private var byContainerUUID: [String: AppRecord] = [:]
    private let iconCache = NSCache<NSString, UIImage>()
    private var missingIcons: Set<String> = []
    private let queue = DispatchQueue(label: "mt2ios.appindex", qos: .utility)
    private var loading = false

    private init() {}

    // MARK: - Loading

    public func loadIfNeeded() {
        guard !ready, !loading else { return }
        loading = true
        queue.async { [weak self] in
            let scanned = AppIndex.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.byBundleID = scanned.byBundleID
                self.byContainerUUID = scanned.byContainer
                self.ready = true
                self.loading = false
            }
        }
    }

    private static func scan() -> (byBundleID: [String: AppRecord], byContainer: [String: AppRecord]) {
        let fm = FileManager.default
        var names: [String: (name: String, path: String)] = [:]
        var records: [String: AppRecord] = [:]
        var byContainer: [String: AppRecord] = [:]

        // 1. Bundle tree -> bundle id, display name, .app path
        let bundleRoot = "/var/containers/Bundle/Application"
        if SandboxEscape.shared.ensureAccess(to: bundleRoot) == nil {
            for uuid in (try? fm.contentsOfDirectory(atPath: bundleRoot)) ?? [] {
                let dir = bundleRoot + "/" + uuid
                for entry in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where entry.hasSuffix(".app") {
                    let appPath = dir + "/" + entry
                    guard let info = NSDictionary(contentsOfFile: appPath + "/Info.plist"),
                          let bundleID = info["CFBundleIdentifier"] as? String else { continue }
                    let display = (info["CFBundleDisplayName"] as? String)
                        ?? (info["CFBundleName"] as? String)
                        ?? bundleID
                    names[bundleID] = (display, appPath)
                }
            }
        }

        // 2. Data containers -> bundle id
        let dataRoot = "/var/mobile/Containers/Data/Application"
        if SandboxEscape.shared.ensureAccess(to: dataRoot) == nil {
            for uuid in (try? fm.contentsOfDirectory(atPath: dataRoot)) ?? [] {
                let container = dataRoot + "/" + uuid
                let metaPath = container + "/.com.apple.mobile_container_manager.metadata.plist"
                guard let meta = NSDictionary(contentsOfFile: metaPath),
                      let bundleID = meta["MCMMetadataIdentifier"] as? String else { continue }

                let info = names[bundleID]
                let record = AppRecord(bundleID: bundleID,
                                       name: info?.name ?? bundleID,
                                       bundlePath: info?.path,
                                       dataContainer: container)
                records[bundleID] = record
                byContainer[uuid] = record
            }
        }

        return (records, byContainer)
    }

    // MARK: - Lookup

    /// Resolves any path inside a data container to its app.
    public func record(forDataPath path: String) -> AppRecord? {
        let components = (path as NSString).pathComponents
        guard let index = components.firstIndex(of: "Application"),
              index + 1 < components.count else { return nil }
        return byContainerUUID[components[index + 1]]
    }

    public func record(forBundleID bundleID: String) -> AppRecord? {
        byBundleID[bundleID]
    }

    public func allApps() -> [AppRecord] {
        byBundleID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// App icon for a container row. Returns nil for non-app rows.
    public func icon(forDataPath path: String) -> UIImage? {
        guard let record = record(forDataPath: path),
              let bundlePath = record.bundlePath else { return nil }
        return icon(forBundlePath: bundlePath)
    }

    public func icon(forBundlePath bundlePath: String) -> UIImage? {
        if let cached = iconCache.object(forKey: bundlePath as NSString) { return cached }
        if missingIcons.contains(bundlePath) { return nil }

        let candidates = [
            "AppIcon60x60@3x.png", "AppIcon60x60@2x.png",
            "AppIcon76x76@2x~ipad.png", "AppIcon83.5x83.5@2x~ipad.png",
            "Icon-60@3x.png", "Icon-60@2x.png", "Icon-72@2x.png", "Icon-76@2x.png"
        ]
        for name in candidates {
            if let image = UIImage(contentsOfFile: bundlePath + "/" + name) {
                iconCache.setObject(image, forKey: bundlePath as NSString)
                return image
            }
        }
        if let files = try? FileManager.default.contentsOfDirectory(atPath: bundlePath) {
            for file in files where file.hasPrefix("AppIcon") && file.hasSuffix(".png") {
                if let image = UIImage(contentsOfFile: bundlePath + "/" + file) {
                    iconCache.setObject(image, forKey: bundlePath as NSString)
                    return image
                }
            }
        }
        missingIcons.insert(bundlePath)
        return nil
    }
}
