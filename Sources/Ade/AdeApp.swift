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
    var seenShots: [Data] = []

    func shot(_ name: String) {
        let url = folder.appendingPathComponent(name)
        guard let image = renderShot(store), writePNG(image, url), let data = try? Data(contentsOf: url) else {
            missing.append(name)
            return
        }
        let score = clayScore(image)
        print(String(format: "preview %@ bytes=%d paper=%.2f yellow=%.2f size=%.0fx%.0f center=%@", name, data.count, score.paperFraction, score.yellowFraction, image.size.width, image.size.height, score.center))
        if data.count < 12_000 || !score.ok {
            missing.append("\(name):not-ui")
            return
        }
        if seenShots.contains(data) {
            missing.append("\(name):duplicate")
            return
        }
        seenShots.append(data)
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
    let root = AnyView(
        RootView()
            .environmentObject(store)
            .frame(width: 1280, height: 800)
            .preferredColorScheme(.light)
    )
    let controller = NSHostingController(rootView: root)
    let window = NSWindow(
        contentRect: NSRect(x: 40, y: 40, width: 1280, height: 800),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.title = "Adê"
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 1280, height: 800))
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    let view = controller.view
    view.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
    view.wantsLayer = true
    for _ in 0..<12 {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.08))
    }
    let candidates = [cacheImage(view), pdfImage(view), layerImage(view)].compactMap { $0 }
    window.orderOut(nil)
    if let clay = candidates.first(where: { clayScore($0).ok }) { return clay }
    return candidates.first
}

private func cacheImage(_ view: NSView) -> NSImage? {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(rep)
    return image
}

private func pdfImage(_ view: NSView) -> NSImage? {
    let data = view.dataWithPDF(inside: view.bounds)
    guard let provider = CGDataProvider(data: data as CFData),
          let document = CGPDFDocument(provider),
          let page = document.page(at: 1) else { return nil }
    let box = page.getBoxRect(.mediaBox)
    guard box.width > 100, box.height > 100 else { return nil }
    let scale: CGFloat = 2
    guard let rep = bitmap(pixelsWide: Int(box.width * scale), pixelsHigh: Int(box.height * scale), pointSize: box.size),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    context.cgContext.drawPDFPage(page)
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: box.size)
    image.addRepresentation(rep)
    return image
}

private func layerImage(_ view: NSView) -> NSImage? {
    guard let layer = view.layer else { return nil }
    let scale = view.window?.backingScaleFactor ?? 2
    let bounds = view.bounds
    guard let rep = bitmap(pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale), pointSize: bounds.size),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.translateBy(x: 0, y: bounds.height * scale)
    context.cgContext.scaleBy(x: scale, y: -scale)
    layer.render(in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: bounds.size)
    image.addRepresentation(rep)
    return image
}

private func bitmap(pixelsWide: Int, pixelsHigh: Int, pointSize: NSSize) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelsWide,
        pixelsHigh: pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = pointSize
    return rep
}

private struct ClayScore {
    var paper = 0
    var yellow = 0
    var samples = 0
    var center = "none"
    var paperFraction: Double { samples == 0 ? 0 : Double(paper) / Double(samples) }
    var yellowFraction: Double { samples == 0 ? 0 : Double(yellow) / Double(samples) }
    var ok: Bool { samples > 20 && yellowFraction < 0.12 && paperFraction > 0.08 }
}

private func clayScore(_ image: NSImage) -> ClayScore {
    var score = ClayScore()
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return score }
    let width = rep.pixelsWide
    let height = rep.pixelsHigh
    let stepX = max(1, width / 48)
    let stepY = max(1, height / 28)
    for y in stride(from: 0, to: height, by: stepY) {
        for x in stride(from: 0, to: width, by: stepX) {
            guard let rgb = rgbAt(rep, x: x, y: y) else { continue }
            score.samples += 1
            if rgb.r > 0.90 && rgb.g > 0.65 && rgb.b < 0.35 { score.yellow += 1 }
            if rgb.r > 0.82 && rgb.g > 0.74 && rgb.b > 0.68 && rgb.b < 0.98 && (rgb.r - rgb.b) > 0.02 && (rgb.r - rgb.b) < 0.22 {
                score.paper += 1
            }
            if x == (width / 2) / stepX * stepX && y == (height / 2) / stepY * stepY {
                score.center = String(format: "%.2f,%.2f,%.2f", rgb.r, rgb.g, rgb.b)
            }
        }
    }
    return score
}

private func rgbAt(_ rep: NSBitmapImageRep, x: Int, y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
    guard let color = rep.colorAt(x: x, y: y) else { return nil }
    let rgb = color.usingColorSpace(.sRGB) ?? color
    guard rgb.numberOfComponents >= 3 else { return nil }
    return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
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
