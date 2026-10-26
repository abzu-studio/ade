import AppKit
import SwiftUI
import AdeCore

@MainActor
enum AdeRuntime {
    static var store: AdeStore!
}

@main
struct AdeApp: App {
    @NSApplicationDelegateAdaptor(AdeDelegate.self) private var delegate
    @StateObject private var store: AdeStore

    init() {
        registerAdeFonts()
        let preview = CommandLine.arguments.contains("--render-previews")
        let store = AdeStore(inMemory: preview)
        _store = StateObject(wrappedValue: store)
        AdeRuntime.store = store
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            AdeMenus(store: store)
        }
    }
}

final class AdeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                installDockIcon()
                AdeRuntime.store.installKeys()
                guard let index = arguments.firstIndex(of: "--render-previews"), arguments.indices.contains(index + 1) else { return }
                capturePreviews(to: arguments[index + 1])
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct AdeMenus: Commands {
    @ObservedObject var store: AdeStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(store.text("spaces.create")) { store.presentNewSpace = true }
                .keyboardShortcut("n")
            Button(store.text("spaces.demo")) { store.perform(.loadDemo) }
        }
        CommandGroup(after: .newItem) {
            Button(store.text("data.backup")) { store.exportBackup() }
            Button(store.text("data.sync")) { store.exportSpace() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(store.space == nil)
            Button(store.text("data.import")) { store.importFile() }
                .keyboardShortcut("o")
            Divider()
            Button(store.text("app.reset")) { store.resetStorage() }
                .disabled(!store.storageError)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(store.text("action.undo")) { store.undo() }
                .keyboardShortcut("z")
                .disabled(!store.canUndo)
            Button(store.text("action.redo")) { store.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.canRedo)
        }
        CommandGroup(after: .sidebar) {
            ForEach(AdeRoute.allCases) { route in
                routeButton(route, index: AdeRoute.allCases.firstIndex(of: route) ?? 0)
            }
        }
        CommandMenu(store.text("common.language")) {
            Button(store.text("common.english")) { store.perform(.setLocale(.en), announce: .none) }
            Button(store.text("common.spanish")) { store.perform(.setLocale(.es), announce: .none) }
        }
    }

    @ViewBuilder
    private func routeButton(_ route: AdeRoute, index: Int) -> some View {
        if index < 9 {
            Button(store.text(route.messageKey)) {
                guard store.space != nil else { return }
                store.go(route)
            }
            .disabled(store.space == nil)
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
        } else {
            Button(store.text(route.messageKey)) {
                guard store.space != nil else { return }
                store.go(route)
            }
            .disabled(store.space == nil)
        }
    }
}

@MainActor
func capturePreviews(to directory: String) {
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = AdeRuntime.store!
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    var missing: [String] = []

    func shot(_ name: String) {
        let url = folder.appendingPathComponent(name)
        guard let image = renderShot(store), writePNG(image, url) else {
            missing.append(name)
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size < 12_000 { missing.append(name) }
    }

    shot("01-home.png")
    store.perform(.loadDemo, announce: .none)
    shot("02-home-demo.png")

    var report = ["formula=\(attendanceFormula)"]
    guard let space = store.database.spaces.first(where: { $0.name == "Demo" }) else {
        report.append("demo=missing")
        try? report.joined(separator: "\n").write(to: folder.appendingPathComponent("attendance-check.txt"), atomically: true, encoding: .utf8)
        exit(1)
    }
    store.open(space.id)
    shot("03-overview.png")

    guard let event = store.database.events.first(where: { $0.spaceId == space.id && $0.title == "February service" }),
          let period = store.database.periods.first(where: { $0.spaceId == space.id && $0.name == "Spring" }) else {
        report.append("demo-records=missing")
        try? report.joined(separator: "\n").write(to: folder.appendingPathComponent("attendance-check.txt"), atomically: true, encoding: .utf8)
        exit(1)
    }
    store.route = .events
    store.eventId = event.id
    shot("04-february-attendance.png")
    store.route = .participation
    shot("05-participation.png")

    let february = computeAttendance(store.database, AttendanceQuery(spaceId: space.id, eventId: event.id))
    report.append(contentsOf: describe("february", february))
    let people = ["Ada", "Ben", "Cia"]
    var peopleOk = true
    for name in people {
        guard let person = store.database.people.first(where: { $0.spaceId == space.id && $0.name == name }) else {
            peopleOk = false
            continue
        }
        let breakdown = computeAttendance(store.database, AttendanceQuery(spaceId: space.id, periodId: period.id, personId: person.id))
        report.append(contentsOf: describe(name.lowercased(), breakdown))
        switch name {
        case "Ada":
            peopleOk = peopleOk && breakdown.present == 3 && breakdown.absent == 0 && breakdown.percentage == 1 && breakdown.excludedCancelled == 1 && breakdown.excludedNotCounting == 1
        case "Ben":
            peopleOk = peopleOk && breakdown.absent == 1 && breakdown.pending == 1 && breakdown.percentage == 0
        case "Cia":
            peopleOk = peopleOk && breakdown.present == 1 && breakdown.excused == 1 && breakdown.denominator == 1 && breakdown.percentage == 1
        default:
            break
        }
    }
    let februaryOk = february.formula == attendanceFormula
        && february.present == 1
        && february.absent == 1
        && february.excused == 1
        && february.pending == 0
        && february.percentage == 0.5
        && formatPercent(february.percentage) == "50.0%"
    report.append("februaryOk=\(februaryOk)")
    report.append("peopleOk=\(peopleOk)")
    report.append("shots=\(missing.isEmpty ? "ok" : missing.joined(separator: ","))")
    try? report.joined(separator: "\n").write(to: folder.appendingPathComponent("attendance-check.txt"), atomically: true, encoding: .utf8)
    print(report.joined(separator: "\n"))
    exit(februaryOk && peopleOk && missing.isEmpty ? 0 : 1)
}

@MainActor
private func renderShot(_ store: AdeStore) -> NSImage? {
    let view = RootView()
        .environmentObject(store)
        .frame(width: 1280, height: 800)
        .preferredColorScheme(.light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(width: 1280, height: 800)
    if let image = renderer.nsImage, image.size.width >= 1000 {
        return image
    }
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    let image = NSImage(size: host.bounds.size)
    image.addRepresentation(rep)
    return image
}

private func writePNG(_ image: NSImage, _ url: URL) -> Bool {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: url)) != nil
}

private func describe(_ name: String, _ breakdown: AttendanceBreakdown) -> [String] {
    [
        "\(name).present=\(breakdown.present)",
        "\(name).absent=\(breakdown.absent)",
        "\(name).excused=\(breakdown.excused)",
        "\(name).pending=\(breakdown.pending)",
        "\(name).denominator=\(breakdown.denominator)",
        "\(name).percentage=\(breakdown.percentage.map { String($0) } ?? "nil")",
        "\(name).formatted=\(formatPercent(breakdown.percentage))",
        "\(name).formula=\(breakdown.formula)",
    ]
}
