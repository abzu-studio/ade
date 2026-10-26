import AppKit
import Observation
import UniformTypeIdentifiers

/// UI state only. Domain transactions, codecs and disk I/O run on LocalStore's executor.
@MainActor @Observable final class AppModel {
  var database = Database()
  var selectedSpace = ""
  var section: AppSection = .summary
  var showSpaces = true
  var welcomeRequested = false
  var quickOpenRequested = false
  var selectedEvent: String?
  var eventTab = 0
  var documentEvent = ""
  var undoSteps: [String: [SessionStep]] = [:]
  var redoSteps: [String: [SessionStep]] = [:]
  var loading = true
  var unreadable = false
  var busy = false
  var error: String?
  var notice = ""
  var pending: Database?
  var locale: String { didSet { preferences.set(locale, forKey: "ade-locale") } }
  var author: String { didSet { preferences.set(author, forKey: "ade-author") } }
  @ObservationIgnored private let preferences: UserDefaults
  @ObservationIgnored private var token = "empty"
  private enum HistoryEffect {
    case none, reset
    case edit(space: String, before: String, label: String)
    case travel(space: String, step: SessionStep, backward: Bool)
    case restore(space: String)
  }
  @ObservationIgnored private var pendingHistory: HistoryEffect = .reset
  let store: LocalStore
  init(directory: URL? = nil, preferences: UserDefaults? = nil) {
    self.store = LocalStore(directory: directory)
    let defaults = preferences ?? (directory.map {
      UserDefaults(suiteName: "AdeIsolated-" + $0.lastPathComponent)!
    } ?? .standard)
    self.preferences = defaults
    locale = defaults.string(forKey: "ade-locale") ?? "es"
    author = defaults.string(forKey: "ade-author") ?? "Local"
  }
  var branch: Branch? { database.spaces.first { $0.id == selectedSpace } }
  var space: Space? { branch?.visible?.data }
  var canEdit: Bool {
    !loading && !unreadable && !busy && pending == nil && branch?.conflicted == false
  }
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
    busy = true
    loading = true
    defer { loading = false; busy = false }
    do {
      let snapshot = try await store.snapshot()
      token = snapshot.token
      database = try snapshot.database.get()
      undoSteps = [:]
      redoSteps = [:]
      unreadable = false
      reconcileSelection()
    } catch {
      unreadable = true
      self.error = error.localizedDescription
    }
  }
  private func reconcileSelection() {
    if !database.spaces.contains(where: { $0.id == selectedSpace }) {
      selectedSpace = database.spaces.first?.id ?? ""
    }
  }
  /// The gate is acquired before the first suspension, including domain preparation.
  /// Failed writes retain the entire proposal; the visible database is never optimistic.
  func commit(_ proposal: Database) async -> Bool {
    guard !busy && !unreadable else { return false }
    if let pending, pending != proposal { return false }
    if pending == nil { pendingHistory = .reset }
    busy = true
    defer { busy = false }
    return await persist(proposal)
  }
  private func persist(_ proposal: Database) async -> Bool {
    pending = proposal
    do {
      let receipt = try await store.commit(proposal, expected: token)
      token = receipt.token
      database = receipt.database
      pending = nil
      finishHistory(merged: receipt.merged)
      if receipt.merged {
        notice = t("Cambios simultáneos conservados. Revisa Conflictos.",
                   "Concurrent changes preserved. Check Conflicts.")
      }
      reconcileSelection()
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  private func finishHistory(merged: Bool) {
    defer { pendingHistory = .reset }
    if merged {
      undoSteps = [:]
      redoSteps = [:]
      return
    }
    switch pendingHistory {
    case .none: break
    case .reset:
      undoSteps = [:]
      redoSteps = [:]
    case .edit(let id, let before, let label):
      guard let branch = database.spaces.first(where: { $0.id == id }),
        !branch.conflicted, let after = branch.heads.first else { return }
      undoSteps[id, default: []].append(SessionStep(before: before, after: after, label: label))
      redoSteps[id] = []
    case .travel(let id, let step, let backward):
      if backward {
        _ = undoSteps[id]?.popLast()
        redoSteps[id, default: []].append(step)
      } else {
        _ = redoSteps[id]?.popLast()
        undoSteps[id, default: []].append(step)
      }
    case .restore(let id):
      undoSteps[id] = []
      redoSteps[id] = []
    }
  }
  @discardableResult private func transact(
    _ mutation: WorkspaceMutation, history: HistoryEffect = .none
  ) async -> Bool {
    guard !busy && !loading && !unreadable && pending == nil else { return false }
    busy = true
    defer { busy = false }
    do {
      let proposal = try await store.prepare(database, mutation: mutation, author: author)
      pendingHistory = history
      return await persist(proposal)
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  func edit(_ command: Edit, label: String) async -> Bool {
    guard canEdit, let before = branch?.heads.first else { return false }
    let spaceID = selectedSpace
    let historyLabel = String(label.prefix(240))
    return await transact(.edit(spaceID, command, historyLabel),
                          history: .edit(space: spaceID, before: before, label: historyLabel))
  }

  func createSpace(name: String, zone: String) async -> Bool {
    let priorIDs = Set(database.spaces.map(\.id))
    guard await transact(.create(name, zone)) else { return false }
    if let added = database.spaces.last(where: { !priorIDs.contains($0.id) }) { openSpace(added.id) }
    return true
  }
  func undo() async { await travel(backward: true) }
  func redo() async { await travel(backward: false) }
  private func travel(backward: Bool) async {
    guard backward ? canUndo : canRedo else { return }
    let spaceID = selectedSpace
    guard let step = (backward ? undoSteps[spaceID] : redoSteps[spaceID])?.last,
      let target = branch?.revisions.first(where: { $0.id == (backward ? step.before : step.after) })
    else { return }
    let label = (backward ? "Deshacer: " : "Rehacer: ") + String(step.label.prefix(225))
    _ = await transact(.append(spaceID, target.data, label),
                       history: .travel(space: spaceID, step: step, backward: backward))
  }
  func restore(_ revision: Revision) async {
    let spaceID = selectedSpace
    _ = await transact(.restore(spaceID, revision.id), history: .restore(space: spaceID))
  }

  func exportWorkspace() {
    let snapshot = pending ?? database
    Task {
      do {
        let data = try await store.export(snapshot)
        try Panels.save(data, name: "Ade-backup.json", type: .json)
      } catch { self.error = error.localizedDescription }
    }
  }
  func importWorkspace() async {
    guard !busy && pending == nil else { return }
    do {
      guard let data = try Panels.open(types: [.json], maxBytes: 100_000_000) else { return }
      if await transact(.importData(data), history: .reset) {
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
      let receipt = try await store.recoverSnapshot(expected: token)
      database = receipt.database
      token = receipt.token
      unreadable = false
      pending = nil
      pendingHistory = .reset
      undoSteps = [:]
      redoSteps = [:]
      reconcileSelection()
      notice = t("Copia anterior restaurada. El archivo dañado se conservó.",
                 "Previous backup restored. The damaged file was preserved.")
    } catch { self.error = error.localizedDescription }
  }
  func recoverBackup() async {
    do {
      let data = try await store.exportBackup()
      try Panels.save(data, name: "Ade-recovered.json", type: .json)
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
