import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable final class AppModel {
  var database = Database()
  var selectedSpace = ""
  var section: AppSection = .summary
  var showSpaces = true
  var welcomeRequested = false
  var selectedEvent: String?
  var eventTab = 0
  var documentEvent = ""
  var undoSteps: [String: [SessionStep]] = [:]
  var redoSteps: [String: [SessionStep]] = [:]
  var canUndo: Bool { canEdit && !(undoSteps[selectedSpace] ?? []).isEmpty }
  var canRedo: Bool { canEdit && !(redoSteps[selectedSpace] ?? []).isEmpty }
  func openSpace(_ id: String) {
    selectedSpace = id
    selectedEvent = nil
    section = .summary
    showSpaces = false
  }
  func openEvent(_ id: String, tab: Int = 0) {
    selectedEvent = id
    eventTab = tab
    section = .events
    showSpaces = false
  }
  func navigate(_ target: AppSection) {
    section = target
    if target == .events { selectedEvent = nil }
    showSpaces = false
  }
  func undo() async { await travel(backward: true) }
  func redo() async { await travel(backward: false) }
  private func travel(backward: Bool) async {
    guard backward ? canUndo : canRedo else { return }
    let spaceID = selectedSpace
    guard let step = (backward ? undoSteps[spaceID] : redoSteps[spaceID])?.last,
      let b = branch,
      let target = b.revisions.first(where: { $0.id == (backward ? step.before : step.after) })
    else { return }
    do {
      let result = try Rules.append(
        database, space: spaceID, data: target.data,
        label: (backward ? "Deshacer: " : "Rehacer: ") + String(step.label.prefix(225)),
        author: author)
      if await commit(result),
        database.spaces.first(where: { $0.id == spaceID })?.conflicted == false
      {
        if backward {
          undoSteps[spaceID]?.removeLast()
          redoSteps[spaceID, default: []].append(step)
        } else {
          redoSteps[spaceID]?.removeLast()
          undoSteps[spaceID, default: []].append(step)
        }
      }
    } catch { self.error = error.localizedDescription }
  }
  var loading = true
  var unreadable = false
  var busy = false
  var error: String?
  var notice = ""
  var pending: Database?
  var locale = UserDefaults.standard.string(forKey: "ade-locale") ?? "es" {
    didSet { UserDefaults.standard.set(locale, forKey: "ade-locale") }
  }
  var author = UserDefaults.standard.string(forKey: "ade-author") ?? "Local" {
    didSet { UserDefaults.standard.set(author, forKey: "ade-author") }
  }
  private var token = "empty"
  let store: LocalStore
  init(directory: URL? = nil) { store = LocalStore(directory: directory) }
  var branch: Branch? { database.spaces.first { $0.id == selectedSpace } }
  var space: Space? { branch?.visible?.data }
  var canEdit: Bool {
    !loading && !unreadable && !busy && pending == nil && branch?.conflicted == false
  }
  func t(_ es: String, _ en: String) -> String { locale == "es" ? es : en }
  func status(_ value: String) -> String {
    let labels = [
      "draft": ("Borrador", "Draft"), "scheduled": ("Programado", "Scheduled"),
      "completed": ("Completado", "Completed"), "cancelled": ("Cancelado", "Cancelled"),
      "present": ("Presente", "Present"), "absent": ("Ausente", "Absent"),
      "excused": ("Excusado", "Excused"), "pending": ("Pendiente", "Pending"),
      "interested": ("Interesado", "Interested"), "selected": ("Seleccionado", "Selected"),
      "declined": ("Declinado", "Declined"),
    ]
    guard let pair = labels[value] else { return value }
    return t(pair.0, pair.1)
  }
  func load() async {
    guard !busy && pending == nil else { return }
    loading = true
    defer { loading = false }
    do {
      let (data, version) = try await store.readData()
      token = version
      let db = try data.map { try WorkspaceCodec.decode($0) } ?? Database()
      database = db
      undoSteps = [:]
      redoSteps = [:]
      token = version
      unreadable = false
      if !db.spaces.contains(where: { $0.id == selectedSpace }) {
        selectedSpace = db.spaces.first?.id ?? ""
      }
    } catch {
      unreadable = true
      self.error = error.localizedDescription
    }
  }
  func commit(_ proposal: Database) async -> Bool {
    guard !busy && !unreadable else { return false }
    busy = true
    pending = proposal
    defer { busy = false }
    do {
      var result = proposal
      do {
        token = try await store.save(
          String(decoding: WorkspaceCodec.encode(result), as: UTF8.self), expected: token)
      } catch StoreError.conflict {
        let (text, newToken) = try await store.load()
        let latest = try text.map { try WorkspaceCodec.decode(Data($0.utf8)) } ?? Database()
        result = try Rules.merge(latest, proposal)
        undoSteps = [:]
        redoSteps = [:]
        pending = result
        token = try await store.save(
          String(decoding: WorkspaceCodec.encode(result), as: UTF8.self), expected: newToken)
        notice = t(
          "Cambios simultáneos conservados. Revisa Historial si hay conflicto.",
          "Concurrent changes preserved. Check History for conflicts.")
      }
      database = result
      pending = nil
      if !result.spaces.contains(where: { $0.id == selectedSpace }) {
        selectedSpace = result.spaces.first?.id ?? ""
      }
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  func edit(_ command: Edit, label: String) async -> Bool {
    guard canEdit else { return false }
    do {
      let spaceID = selectedSpace
      let before = branch!.heads[0]
      let result = try Rules.execute(
        database, space: spaceID, edit: command, label: label, author: author)
      let after = result.spaces.first { $0.id == spaceID }!.heads[0]
      let saved = await commit(result)
      if saved && database.spaces.first(where: { $0.id == spaceID })?.heads == [after] {
        undoSteps[spaceID, default: []].append(
          SessionStep(before: before, after: after, label: label))
        redoSteps[spaceID] = []
      }
      return saved
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  func createSpace(name: String, zone: String) async -> Bool {
    do {
      let next = try Rules.create(database, name: name, author: author, zone: zone)
      if await commit(next) {
        openSpace(next.spaces.last!.id)
        return true
      }
      return false
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  func restore(_ revision: Revision) async {
    undoSteps[selectedSpace] = []
    redoSteps[selectedSpace] = []
    do {
      _ = await commit(
        try Rules.restore(database, space: selectedSpace, revision: revision.id, author: author))
    } catch { self.error = error.localizedDescription }
  }
  func exportWorkspace() {
    do {
      try Panels.save(
        WorkspaceCodec.encode(pending ?? database), name: "Ade-backup.json", type: .json)
    } catch { self.error = error.localizedDescription }
  }
  func importWorkspace() async {
    guard !busy && pending == nil else { return }
    do {
      guard let data = try Panels.open(types: [.json], maxBytes: 100_000_000) else { return }
      if await commit(try Rules.merge(database, WorkspaceCodec.decode(data))) {
        undoSteps = [:]
        redoSteps = [:]
        showSpaces = false
      }
    } catch { self.error = error.localizedDescription }
  }
  func repairFromBackup() async {
    guard !busy && unreadable else { return }
    busy = true
    defer { busy = false }
    do {
      let (text, version) = try await store.recoverPrevious(expected: token)
      database = try WorkspaceCodec.decode(Data(text.utf8))
      token = version
      unreadable = false
      pending = nil
      selectedSpace = database.spaces.first?.id ?? ""
      notice = t(
        "Copia anterior restaurada. El archivo dañado se conservó.",
        "Previous backup restored. The damaged file was preserved.")
    } catch { self.error = error.localizedDescription }
  }
  func recoverBackup() async {
    do {
      guard let text = try await store.backup() else { throw RuleError("No hay copia anterior") }
      let db = try WorkspaceCodec.decode(Data(text.utf8))
      // Export recovery first; never overwrite an unreadable current file automatically.
      try Panels.save(WorkspaceCodec.encode(db), name: "Ade-recovered.json", type: .json)
    } catch { self.error = error.localizedDescription }
  }
}
@MainActor enum Panels {
  static func open(types: [UTType], maxBytes: Int = 10_000_000) throws -> Data? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = types
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    try require(size <= maxBytes, "El archivo supera el tamaño permitido")
    let data = try Data(contentsOf: url)
    try require(data.count <= maxBytes, "El archivo supera el tamaño permitido")
    return data
  }
  static func save(_ data: Data, name: String, type: UTType) throws {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [type]
    panel.nameFieldStringValue = name
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    try data.write(to: url, options: .atomic)
  }
}
struct SessionStep {
  var before: String
  var after: String
  var label: String
}
enum AppSection: String, CaseIterable, Identifiable {
  case summary, people, groups, periods, classification, events, results, documents, history, data,
    conflicts, rules, settings
  static var navigation: [Self] { allCases.filter { $0 != .settings } }
  var id: String { rawValue }
  var number: String { String(format: "%02d", (Self.navigation.firstIndex(of: self) ?? 0) + 1) }
  @MainActor func title(_ m: AppModel) -> String {
    switch self {
    case .summary: m.t("Resumen", "Overview")
    case .people: m.t("Personas", "People")
    case .groups: m.t("Grupos", "Groups")
    case .periods: m.t("Períodos", "Periods")
    case .classification: m.t("Componentes", "Components")
    case .events: m.t("Eventos", "Events")
    case .results: m.t("Participación", "Participation")
    case .documents: m.t("Documentos", "Documents")
    case .history: m.t("Historial", "History")
    case .data: m.t("Datos", "Data")
    case .conflicts: m.t("Conflictos", "Conflicts")
    case .rules: m.t("Reglas", "Rules")
    case .settings: m.t("Configuración", "Settings")
    }
  }
}
