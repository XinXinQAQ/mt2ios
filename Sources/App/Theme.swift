//
//  Theme.swift
//  mt2ios
//
//  Palette lifted from MT2's res/values/colors.xml so the two apps look like
//  the same product: #303030 toolbar, #607D8B file glyphs, #65C0DF selection,
//  #039BE5 dialog buttons, 43dp rows with a 28dp icon frame.
//

import SwiftUI

public enum Theme {
    public static let toolbar      = Color(red: 0.188, green: 0.188, blue: 0.188) // #303030
    public static let gray         = Color(red: 0.392, green: 0.392, blue: 0.392) // #646464
    public static let accent       = Color(red: 0.012, green: 0.608, blue: 0.898) // #039BE5
    public static let selection    = Color(red: 0.396, green: 0.753, blue: 0.874) // #65C0DF
    public static let fileBlue     = Color(red: 0.376, green: 0.490, blue: 0.545) // #607D8B

    public static let rowHeight: CGFloat   = 43
    public static let iconFrame: CGFloat   = 28
    public static let actionBarHeight: CGFloat = 50

    public static func listBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.106, green: 0.110, blue: 0.118) : .white
    }

    public static func paneChrome(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.145, green: 0.149, blue: 0.157) : Color(white: 0.965)
    }

    public static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.93) : Color(white: 0.06)
    }

    public static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.24) : Color(white: 0.88)
    }

    public static func selectionFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? selection.opacity(0.30) : selection.opacity(0.35)
    }
}
