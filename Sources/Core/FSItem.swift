//
//  FSItem.swift
//  mt2ios
//
//  A single directory entry. Everything shown in the list comes from lstat(),
//  so the numbers match what the kernel reports rather than what
//  FileManager's cached attributes claim.
//

import Foundation
import Darwin
import SwiftUI

public enum SortMode: String, CaseIterable, Identifiable, Codable {
    case nameAsc, nameDesc, dateDesc, dateAsc, sizeDesc, sizeAsc, kindAsc

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nameAsc:  return "名称 ↑"
        case .nameDesc: return "名称 ↓"
        case .dateDesc: return "修改时间 ↓"
        case .dateAsc:  return "修改时间 ↑"
        case .sizeDesc: return "大小 ↓"
        case .sizeAsc:  return "大小 ↑"
        case .kindAsc:  return "类型"
        }
    }
}

public struct FSItem: Identifiable, Hashable {
    public var id: String { path }

    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let size: Int64
    public let modified: Date
    public let mode: UInt16

    public init(path: String) {
        self.path = path
        self.name = (path as NSString).lastPathComponent

        var st = stat()
        let ok = lstat(path, &st) == 0
        let type = ok ? (st.st_mode & S_IFMT) : 0

        self.isDirectory = ok && type == S_IFDIR
        self.isSymlink   = ok && type == S_IFLNK
        self.size        = (ok && type != S_IFDIR) ? Int64(st.st_size) : 0
        self.modified    = ok ? Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                              : Date(timeIntervalSince1970: 0)
        self.mode        = ok ? st.st_mode : 0
    }

    // MARK: - Presentation

    public var extensionName: String {
        isDirectory ? "" : (name as NSString).pathExtension.lowercased()
    }

    public var typeChar: String {
        if isSymlink { return "l" }
        if isDirectory { return "d" }
        return "-"
    }

    /// rwxr-xr-x style string, 9 characters, no type prefix.
    public var permissionText: String {
        let bits: [(UInt16, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        var out = ""
        for (bit, ch) in bits {
            if mode & bit != 0 {
                out.append(ch)
            } else if bit == 0o100 && mode & 0o4000 != 0 {
                out.append("s")
            } else if bit == 0o010 && mode & 0o2000 != 0 {
                out.append("s")
            } else if bit == 0o001 && mode & 0o1000 != 0 {
                out.append("t")
            } else {
                out.append("-")
            }
        }
        return out
    }

    public var sizeText: String {
        if isDirectory { return "--" }
        if isSymlink { return "link" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public var dateText: String {
        if modified.timeIntervalSince1970 == 0 { return "--" }
        return FSItem.dateFormatter.string(from: modified)
    }

    public var iconName: String {
        if isSymlink { return "arrowshape.turn.up.right" }
        if isDirectory { return "folder.fill" }
        switch extensionName {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp", "svg":
            return "photo.fill"
        case "mp4", "mov", "m4v", "avi", "mkv", "webm":
            return "film.fill"
        case "mp3", "m4a", "wav", "aac", "flac", "caf", "ogg":
            return "waveform"
        case "zip", "7z", "rar", "tar", "gz", "xz", "deb", "ipa":
            return "archivebox.fill"
        case "plist", "strings", "entitlements":
            return "list.bullet.rectangle.fill"
        case "json", "xml", "yaml", "yml", "toml":
            return "curlybraces"
        case "swift", "m", "mm", "h", "c", "cpp", "js", "ts", "py", "sh", "lua", "kt", "java":
            return "chevron.left.forwardslash.chevron.right"
        case "dylib", "so", "framework":
            return "shippingbox.fill"
        case "db", "sqlite", "sqlite3", "realm":
            return "cylinder.split.1x2.fill"
        case "ttf", "otf", "ttc":
            return "textformat"
        case "car", "bundle", "app":
            return "cube.fill"
        default:
            return "doc.fill"
        }
    }

    public var tint: Color {
        if isSymlink { return Color(red: 0.36, green: 0.62, blue: 0.86) }
        if isDirectory { return Color(red: 0.376, green: 0.490, blue: 0.545) } // MT2 #607D8B
        switch extensionName {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "svg":
            return Color(red: 0.85, green: 0.45, blue: 0.35)
        case "mp4", "mov", "m4v", "mkv":
            return Color(red: 0.55, green: 0.42, blue: 0.75)
        case "mp3", "m4a", "wav", "flac", "caf":
            return Color(red: 0.35, green: 0.65, blue: 0.60)
        case "plist", "json", "xml", "yaml", "yml", "entitlements":
            return Color(red: 0.42, green: 0.55, blue: 0.32)
        case "dylib", "so", "db", "sqlite", "sqlite3":
            return Color(red: 0.50, green: 0.45, blue: 0.35)
        default:
            return Color(red: 0.45, green: 0.52, blue: 0.60)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
