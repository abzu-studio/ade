import CryptoKit
import Darwin
import Foundation

/// A transaction's input is immutable and captured before leaving the main actor.
enum WorkspaceMutation {
  case edit(String, Edit, String)
  case create(String, String)
  case append(String, Space, String)
  case restore(String, String)
  case importData(Data)
}
struct WorkspaceReceipt {
  let database: Database
  let token: String
  let merged: Bool
}
struct WorkspaceSnapshot {
  let database: Result<Database, Error>
  let token: String
}

/// Owns domain preparation, validation, serialization and atomic disk transactions.
/// The actor serializes this process; flock also coordinates other Adê processes.
actor LocalStore {
  let directory: URL
  init(directory: URL? = nil) {
    self.directory = directory ?? FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Adê", isDirectory: true)
  }
  private var current: URL { directory.appendingPathComponent("workspace.json") }
  private var previous: URL { directory.appendingPathComponent("workspace.previous.json") }
  private func token(_ data: Data?) -> String {
    guard let data else { return "empty" }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  func readData() throws -> (Data?, String) {
    guard FileManager.default.fileExists(atPath: current.path) else { return (nil, "empty") }
    let data = try Data(contentsOf: current)
    return (data, token(data))
  }
  func snapshot() throws -> WorkspaceSnapshot {
    let (data, version) = try readData()
    // Retain the hash even when decoding fails, so recovery still uses compare-and-swap.
    return WorkspaceSnapshot(database: Result {
      try data.map(WorkspaceCodec.decode) ?? Database()
    }, token: version)
  }
  func prepare(_ db: Database, mutation: WorkspaceMutation, author: String) throws -> Database {
    switch mutation {
    case .edit(let id, let edit, let label):
      return try Rules.execute(db, space: id, edit: edit, label: label, author: author)
    case .create(let name, let zone):
      return try Rules.create(db, name: name, author: author, zone: zone)
    case .append(let id, let space, let label):
      return try Rules.append(db, space: id, data: space, label: label, author: author)
    case .restore(let id, let revision):
      return try Rules.restore(db, space: id, revision: revision, author: author)
    case .importData(let data):
      return try Rules.merge(db, WorkspaceCodec.decode(data))
    }
  }
  func report(_ space: Space, filter: ReportFilter) throws -> [String: Participation] {
    try Rules.report(space, filter: filter)
  }
  func breakdown(_ space: Space, person: String, period: String, group: String) throws -> [ParticipationSlice] {
    try Rules.participationBreakdown(space, person: person, period: period, group: group)
  }
  func revisionText(_ space: Space) throws -> String {
    String(decoding: try WorkspaceCodec.encode(space), as: UTF8.self)
  }
  func export(_ db: Database) throws -> Data { try WorkspaceCodec.encode(db) }
  func exportBackup() throws -> Data {
    guard let text = try backup() else { throw RuleError("No hay copia anterior") }
    return try WorkspaceCodec.encode(WorkspaceCodec.decode(Data(text.utf8)))
  }
  private func locked<T>(_ operation: () throws -> T) throws -> T {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let descriptor = Darwin.open(directory.appendingPathComponent("workspace.lock").path,
                                 O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw StoreError.invalidRequest }
    defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.invalidRequest }
    return try operation()
  }
  private func write(_ data: Data, prior: Data?) throws {
    if let prior {
      let migration = directory.appendingPathComponent("workspace.before-native.json")
      if !FileManager.default.fileExists(atPath: migration.path) {
        try prior.write(to: migration, options: .atomic)
      }
      try prior.write(to: previous, options: .atomic)
    }
    try data.write(to: current, options: .atomic)
  }
  /// Merge and write share one OS lock: another process cannot slip between them.
  func commit(_ proposal: Database, expected: String) throws -> WorkspaceReceipt {
    try Rules.validate(proposal)
    return try locked {
      let (prior, version) = try readData()
      let merged = version != expected
      let result: Database
      if merged {
        let latest = try prior.map(WorkspaceCodec.decode) ?? Database()
        result = try Rules.merge(latest, proposal)
      } else { result = proposal }
      let data = try WorkspaceCodec.encode(result)
      try require(data.count <= 100_000_000, "El archivo supera 100 MB.")
      try write(data, prior: prior)
      return WorkspaceReceipt(database: result, token: token(data), merged: merged)
    }
  }
  // Compatibility API for JSON tools and strict compare-and-swap callers.
  func load() throws -> (String?, String) {
    let (data, version) = try readData()
    guard let data else { return (nil, version) }
    guard let text = String(data: data, encoding: .utf8) else { throw StoreError.invalidData }
    return (text, version)
  }
  func save(_ text: String, expected: String) throws -> String {
    try locked {
      let (prior, version) = try readData()
      guard version == expected else { throw StoreError.conflict }
      let data = Data(text.utf8)
      _ = try WorkspaceCodec.decode(data)
      try write(data, prior: prior)
      return token(data)
    }
  }
  func recoverSnapshot(expected: String) throws -> WorkspaceReceipt {
    try locked {
      let (prior, version) = try readData()
      guard version == expected else { throw StoreError.conflict }
      let data = try Data(contentsOf: previous)
      let database = try WorkspaceCodec.decode(data)
      if let prior {
        try prior.write(to: directory.appendingPathComponent(
          "workspace.recovered-" + UUID().uuidString + ".json"), options: .atomic)
      }
      try data.write(to: current, options: .atomic)
      return WorkspaceReceipt(database: database, token: token(data), merged: false)
    }
  }
  func recoverPrevious(expected: String) throws -> (String, String) {
    let receipt = try recoverSnapshot(expected: expected)
    return (String(decoding: try WorkspaceCodec.encode(receipt.database), as: UTF8.self), receipt.token)
  }
  func backup() throws -> String? {
    guard FileManager.default.fileExists(atPath: previous.path) else { return nil }
    return try String(contentsOf: previous, encoding: .utf8)
  }
}
enum StoreError: LocalizedError {
  case conflict, invalidData, invalidRequest
  var errorDescription: String? {
    switch self {
    case .conflict: "Los datos cambiaron en otra ventana. Recarga antes de continuar."
    case .invalidData: "El archivo de datos no es válido. El original se conserva."
    case .invalidRequest: "Solicitud nativa no permitida."
    }
  }
}
