import AppKit
import Foundation
import UniformTypeIdentifiers
import AdeCore

enum Announce {
    case saved, imported, none
}

@MainActor
final class AdeStore: ObservableObject {
    @Published var database: Database
    @Published var spaceId: String?
    @Published var route: AdeRoute = .overview
    @Published var eventId: String?
    @Published var personId: String?
    @Published var groupId: String?
    @Published var templateId: String?
    @Published var storageError = false
    @Published var lastError: String?
    @Published var toast: String?
    @Published var confirmBackup = false
    @Published var presentNewSpace = false
    @Published var attendancePeople: [String] = []
    @Published var attendanceIndex = 0

    let inMemory: Bool
    private let fileURL: URL?
    private var holdCorrupt = false
    private var pendingImport: JSONValue?
    private var toastToken = 0
    private var keyMonitor: Any?
    private let english: [String: String]
    private let spanish: [String: String]

    init(inMemory: Bool) {
        self.inMemory = inMemory
        english = Self.loadCatalog("en")
        spanish = Self.loadCatalog("es")
        if inMemory {
            fileURL = nil
            database = createEmptyDatabase(actorId: "local", now: isoTimestamp())
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Adê", isDirectory: true)
            fileURL = root.appendingPathComponent("database.json")
            database = createEmptyDatabase(actorId: UUID().uuidString, now: isoTimestamp())
            load()
        }
    }

    var space: Space? { database.spaces.first { $0.id == spaceId } }

    var locale: AdeLocale { database.locale }

    func text(_ key: String, _ params: [String: String] = [:]) -> String {
        var value = (locale == .es ? spanish : english)[key] ?? english[key] ?? key
        for (name, replacement) in params {
            value = value.replacingOccurrences(of: "{\(name)}", with: replacement)
        }
        return value
    }

    func errorText(_ error: CoreError) -> String {
        text("error.\(error.code.rawValue)", error.params)
    }

    func people(in spaceId: String) -> [Person] {
        database.people.filter { $0.spaceId == spaceId }.sorted(by: byName)
    }

    func groups(in spaceId: String) -> [AdeCore.Group] {
        database.groups.filter { $0.spaceId == spaceId }.sorted(by: byName)
    }

    func periods(in spaceId: String) -> [Period] {
        database.periods.filter { $0.spaceId == spaceId }.sorted { $0.startDate == $1.startDate ? $0.name < $1.name : $0.startDate < $1.startDate }
    }

    func components(in spaceId: String) -> [ActivityComponent] {
        database.components.filter { $0.spaceId == spaceId }.sorted(by: byName)
    }

    func categories(in spaceId: String, componentId: String? = nil) -> [AdeCore.Category] {
        database.categories.filter { $0.spaceId == spaceId && (componentId == nil || $0.componentId == componentId) }.sorted(by: byName)
    }

    func events(in spaceId: String) -> [AdeEvent] {
        database.events.filter { $0.spaceId == spaceId }.sorted {
            $0.date == $1.date ? byName($0.title, $1.title) : $0.date < $1.date
        }
    }

    func templates(in spaceId: String) -> [DocumentTemplate] {
        database.templates.filter { $0.spaceId == spaceId }.sorted(by: byName)
    }

    func assets(in spaceId: String) -> [Asset] {
        database.assets.filter { $0.spaceId == spaceId && $0.deletedAt == nil }.sorted(by: byName)
    }

    func pendingConflicts(in spaceId: String) -> [ConflictRecord] {
        database.conflicts.filter { $0.spaceId == spaceId && $0.resolution == .pending }
    }

    var canUndoSpace: Bool {
        guard let spaceId, let history = database.histories.first(where: { $0.spaceId == spaceId }) else { return false }
        return history.cursor >= 0
    }

    var canRedoSpace: Bool {
        guard let spaceId, let history = database.histories.first(where: { $0.spaceId == spaceId }) else { return false }
        return history.cursor < history.revisionIds.count - 1
    }

    var canUndo: Bool {
        if textViewCanUndo { return true }
        return canUndoSpace
    }

    var canRedo: Bool {
        if textViewCanRedo { return true }
        return canRedoSpace
    }

    func open(_ id: String) {
        spaceId = id
        route = .overview
        eventId = nil
        personId = nil
        groupId = nil
        templateId = nil
        attendancePeople = []
        attendanceIndex = 0
    }

    func goHome() {
        spaceId = nil
        eventId = nil
    }

    func go(_ route: AdeRoute) {
        self.route = route
    }

    func perform(_ action: Action, announce: Announce = .saved) {
        switch dispatch(database, action, context()) {
        case .ok(let next):
            database = next
            if let spaceId, !database.spaces.contains(where: { $0.id == spaceId }) {
                self.spaceId = nil
            }
            storageError = false
            holdCorrupt = false
            lastError = nil
            persist()
            switch announce {
            case .saved: flash(text("common.saved"))
            case .imported: flash(text("data.imported"))
            case .none: break
            }
        case .err(let error):
            lastError = errorText(error)
        }
    }

    func undo() {
        if forwardEdit(redo: false) { return }
        guard let spaceId else {
            lastError = text("error.NOTHING_TO_UNDO")
            return
        }
        perform(.undo(spaceId: spaceId), announce: .none)
    }

    func redo() {
        if forwardEdit(redo: true) { return }
        guard let spaceId else {
            lastError = text("error.NOTHING_TO_REDO")
            return
        }
        perform(.redo(spaceId: spaceId), announce: .none)
    }

    func resetStorage() {
        let actor = database.actor
        database = createEmptyDatabase(actorId: actor.id, now: isoTimestamp(), actorName: actor.name)
        spaceId = nil
        storageError = false
        holdCorrupt = false
        lastError = nil
        toast = nil
        persist()
    }

    func dismissError() { lastError = nil }

    func exportBackup() {
        guard let data = try? encodeJSON(toBackup(database, exportedAt: isoTimestamp()), pretty: true) else { return }
        savePanel(data: data, name: "ade-backup.json", type: .json)
    }

    func exportSpace() {
        guard let spaceId, let space else { return }
        switch toSyncBundle(database, spaceId: spaceId, exportedAt: isoTimestamp()) {
        case .ok(let bundle):
            guard let data = try? encodeJSON(bundle, pretty: true) else { return }
            savePanel(data: data, name: exportName(space.name), type: .json)
        case .err(let error):
            lastError = errorText(error)
        }
    }

    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                self?.readImport(url)
            }
        }
    }

    func commitBackup() {
        guard let pendingImport else { return }
        self.pendingImport = nil
        confirmBackup = false
        perform(.importBackup(pendingImport), announce: .imported)
    }

    func cancelBackup() {
        pendingImport = nil
        confirmBackup = false
    }

    func savePanel(data: Data, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                do {
                    try data.write(to: url, options: .atomic)
                    self?.flash(self?.text("common.saved") ?? "Saved")
                } catch {
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    func chooseAsset() {
        guard let spaceId else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                self?.addAsset(spaceId: spaceId, url: url)
            }
        }
    }

    func documentLabels() -> DocumentLabels {
        DocumentLabels(
            unrecorded: text("attendance.unrecorded"),
            attendance: [
                .present: text("attendance.present"),
                .absent: text("attendance.absent"),
                .excused: text("attendance.excused"),
                .pending: text("attendance.pending"),
            ],
            volunteer: [
                .interested: text("volunteer.interested"),
                .selected: text("volunteer.selected"),
                .completed: text("volunteer.completed"),
                .declined: text("volunteer.declined"),
                .absent: text("volunteer.absent"),
            ],
            eventStatus: [
                .draft: text("status.draft"),
                .scheduled: text("status.scheduled"),
                .completed: text("status.completed"),
                .cancelled: text("status.cancelled"),
            ],
            percent: formatPercent,
            counts: { present, absent in "\(present)/\(present + absent)" },
            separator: " - "
        )
    }

    func revisionText(_ revision: Revision) -> String {
        let key = "revision.\(revision.action)"
        guard english[key] != nil else { return revision.action }
        var params = revision.params
        if revision.action == "setAttendance", let state = params["state"] {
            params["state"] = text("attendance.\(state)")
        }
        if revision.action == "setVolunteerState", let state = params["state"] {
            params["state"] = text("volunteer.\(state)")
        }
        if let status = params["status"], english["status.\(status)"] != nil {
            params["status"] = text("status.\(status)")
        }
        switch params["resolution"] {
        case "kept-local": params["resolution"] = text("conflicts.keepLocal")
        case "kept-remote": params["resolution"] = text("conflicts.keepRemote")
        case "kept-both": params["resolution"] = text("conflicts.keepBoth")
        default: break
        }
        return text(key, params)
    }

    func setAttendanceRoster(_ ids: [String]) {
        attendancePeople = ids
        if attendanceIndex >= ids.count { attendanceIndex = max(0, ids.count - 1) }
    }

    func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
    }

    func flash(_ message: String) {
        toastToken += 1
        let token = toastToken
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.toast = nil
        }
    }

    private func handleKey(_ key: NSEvent) -> Bool {
        if key.modifierFlags.contains(.command) || key.modifierFlags.contains(.control) || key.modifierFlags.contains(.option) {
            return false
        }
        if NSApp.keyWindow?.firstResponder is NSTextView { return false }
        guard route == .events, let spaceId, let eventId else { return false }
        guard let record = database.events.first(where: { $0.id == eventId }),
              record.status == .scheduled || record.status == .completed else { return false }
        guard !attendancePeople.isEmpty else { return false }
        let chars = key.charactersIgnoringModifiers?.lowercased() ?? ""
        switch chars {
        case "p": markAttendance(.present, spaceId: spaceId, eventId: eventId)
        case "a": markAttendance(.absent, spaceId: spaceId, eventId: eventId)
        case "e": markAttendance(.excused, spaceId: spaceId, eventId: eventId)
        case "w": markAttendance(.pending, spaceId: spaceId, eventId: eventId)
        default:
            if key.keyCode == 126 { moveAttendance(-1); return true }
            if key.keyCode == 125 { moveAttendance(1); return true }
            return false
        }
        return true
    }

    private func markAttendance(_ state: AttendanceState, spaceId: String, eventId: String) {
        guard attendancePeople.indices.contains(attendanceIndex) else { return }
        let personId = attendancePeople[attendanceIndex]
        let note = database.attendance.first { $0.eventId == eventId && $0.personId == personId }?.note ?? ""
        perform(.setAttendance(spaceId: spaceId, eventId: eventId, personId: personId, state: state, note: note))
    }

    private func moveAttendance(_ delta: Int) {
        guard !attendancePeople.isEmpty else { return }
        let count = attendancePeople.count
        attendanceIndex = (attendanceIndex + delta + count) % count
    }

    private var textViewCanUndo: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.canUndo == true
    }

    private var textViewCanRedo: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.canRedo == true
    }

    private func forwardEdit(redo: Bool) -> Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, let manager = editor.undoManager else { return false }
        if redo {
            guard manager.canRedo else { return false }
            manager.redo()
        } else {
            guard manager.canUndo else { return false }
            manager.undo()
        }
        return true
    }

    private func context() -> ReduceContext {
        ReduceContext(now: isoTimestamp(), actorId: database.actor.id, newId: { UUID().uuidString })
    }

    private func load() {
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            persist()
            return
        }
        do {
            let json = try JSONValue.parse(Data(contentsOf: fileURL))
            switch sanitizeDatabase(json) {
            case .ok(let loaded):
                database = loaded
            case .err:
                storageError = true
                holdCorrupt = true
            }
        } catch {
            storageError = true
            holdCorrupt = true
        }
    }

    private func persist() {
        guard !inMemory, !holdCorrupt, let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encodeJSON(database, pretty: true).write(to: fileURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func readImport(_ url: URL) {
        do {
            let json = try JSONValue.parse(Data(contentsOf: url))
            if case .object(let fields) = json, case .string(let format) = fields["format"], format == backupFormat {
                pendingImport = json
                confirmBackup = true
                return
            }
            perform(.importSync(json), announce: .imported)
        } catch {
            lastError = text("error.INVALID_IMPORT")
        }
    }

    private func addAsset(spaceId: String, url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let mime: AssetMime
        switch url.pathExtension.lowercased() {
        case "png": mime = .png
        case "jpg", "jpeg": mime = .jpeg
        case "pdf": mime = .pdf
        default:
            lastError = text("error.ASSET_NOT_FOUND")
            return
        }
        perform(.addAsset(spaceId: spaceId, name: url.deletingPathExtension().lastPathComponent, mime: mime, dataBase64: data.base64EncodedString()))
    }

    private func exportName(_ name: String) -> String {
        let slug = name.lowercased().unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let compact = slug.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return "ade-\(compact.isEmpty ? "space" : compact).json"
    }

    private static func loadCatalog(_ name: String) -> [String: String] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return object
    }
}

private func byName<T>(_ lhs: T, _ rhs: T) -> Bool where T: Named {
    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
}

private func byName(_ lhs: String, _ rhs: String) -> Bool {
    lhs.localizedStandardCompare(rhs) == .orderedAscending
}

private protocol Named { var name: String { get } }
extension Person: Named {}
extension AdeCore.Group: Named {}
extension ActivityComponent: Named {}
extension AdeCore.Category: Named {}
extension DocumentTemplate: Named {}
extension Asset: Named {}

func formatWhen(_ iso: String, locale: AdeLocale) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fallback = ISO8601DateFormatter()
    let date = parser.date(from: iso) ?? fallback.date(from: iso) ?? Date()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: locale == .es ? "es" : "en")
    formatter.timeZone = TimeZone(identifier: "America/Puerto_Rico")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date) + " (Puerto Rico)"
}

func todayISO() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/Puerto_Rico")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

func jsonPreview(_ value: JSONValue) -> String {
    let text = canonical(value)
    if text.count > 700 { return String(text.prefix(700)) + "…" }
    return text
}

enum WholeNumber {
    case unlimited
    case value(Int)
    case invalid
}

func wholeNumber(_ raw: String) -> WholeNumber {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .unlimited }
    guard let value = Int(trimmed), value >= 0 else { return .invalid }
    return .value(value)
}
