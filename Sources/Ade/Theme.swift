import AppKit
import CoreText
import SwiftUI

enum Clay {
    static let ink = Color(red: 184 / 255, green: 68 / 255, blue: 26 / 255)
    static let umber = Color(red: 74 / 255, green: 42 / 255, blue: 24 / 255)
    static let tint = Color(red: 229 / 255, green: 201 / 255, blue: 176 / 255)
    static let cream = Color(red: 250 / 255, green: 246 / 255, blue: 238 / 255)
    static let paper = Color(red: 237 / 255, green: 230 / 255, blue: 214 / 255)
    static let tintWash = Color(red: 229 / 255, green: 201 / 255, blue: 176 / 255, opacity: 0.55)
}

enum AdeFont {
    static func display(_ size: CGFloat) -> Font {
        .custom("BarlowCondensed-ExtraBold", size: size)
    }

    static func kicker(_ size: CGFloat = 11) -> Font {
        .custom("IBMPlexMono-Medium", size: size)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .custom("Inter-Regular", size: size)
    }

    static func medium(_ size: CGFloat = 15) -> Font {
        .custom("Inter-Medium", size: size)
    }
}

enum AdeRoute: String, CaseIterable, Identifiable {
    case overview, people, groups, periods, components, events, participation, documents, history, conflicts, data, rules

    var id: String { rawValue }

    var messageKey: String {
        switch self {
        case .overview: return "nav.overview"
        case .people: return "nav.people"
        case .groups: return "nav.groups"
        case .periods: return "nav.periods"
        case .components: return "nav.taxonomy"
        case .events: return "nav.events"
        case .participation: return "nav.participation"
        case .documents: return "nav.documents"
        case .history: return "nav.history"
        case .conflicts: return "nav.conflicts"
        case .data: return "nav.data"
        case .rules: return "nav.rules"
        }
    }
}

enum Marks {
    static let menu = image("ade-menu-icon-256")
    static let menuSmall = image("ade-menu-icon-32")

    static func image(_ name: String) -> NSImage {
        let url = Bundle.module.url(forResource: name, withExtension: "png")
        return url.flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: NSSize(width: 32, height: 32))
    }
}

func registerAdeFonts() {
    let names = ["BarlowCondensed-ExtraBold", "IBMPlexMono-Medium", "Inter-Regular", "Inter-Medium"]
    for name in names {
        let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.module.url(forResource: name, withExtension: "ttf")
        guard let url else { continue }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

func installDockIcon() {
    guard let url = Bundle.module.url(forResource: "ade-app-icon-1024", withExtension: "png"),
          let image = NSImage(contentsOf: url) else { return }
    NSApplication.shared.applicationIconImage = image
}
