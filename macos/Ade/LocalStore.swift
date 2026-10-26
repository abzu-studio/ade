import CryptoKit
import Darwin
import Foundation

/// Atomic local persistence with cross-process locking and compare-and-swap.
actor LocalStore {
  let directory: URL
  init(directory: URL? = nil) {
    self.directory =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
  func load() throws -> (String?, String) {
    guard FileManager.default.fileExists(atPath: current.path) else { return (nil, "empty") }
    let data = try Data(contentsOf: current)
    guard let text = String(data: data, encoding: .utf8) else { throw StoreError.invalidData }
    return (text, token(data))
  }
  func save(_ text: String, expected: String) throws -> String {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let lockPath = directory.appendingPathComponent("workspace.lock").path
    let descriptor = Darwin.open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw StoreError.invalidRequest }
    defer {
      flock(descriptor, LOCK_UN)
      Darwin.close(descriptor)
    }
    guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.invalidRequest }
    let prior =
      FileManager.default.fileExists(atPath: current.path) ? try Data(contentsOf: current) : nil
    guard token(prior) == expected else { throw StoreError.conflict }
    let data = Data(text.utf8)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      json["schemaVersion"] as? Int == 1
    else { throw StoreError.invalidData }
    _ = try WorkspaceCodec.decode(data)
    if let prior {
      let migration = directory.appendingPathComponent("workspace.before-native.json")
      if !FileManager.default.fileExists(atPath: migration.path) {
        try prior.write(to: migration, options: [.atomic])
      }
      try prior.write(to: previous, options: [.atomic])
    }
    try data.write(to: current, options: [.atomic])
    return token(data)
  }
  /// Explicit recovery only: retain the unreadable file before restoring a validated backup.
  func recoverPrevious(expected: String) throws -> (String, String) {
    let data = try Data(contentsOf: previous)
    _ = try WorkspaceCodec.decode(data)
    let descriptor = Darwin.open(
      directory.appendingPathComponent("workspace.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw StoreError.invalidRequest }
    defer {
      flock(descriptor, LOCK_UN)
      Darwin.close(descriptor)
    }
    guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.invalidRequest }
    let prior =
      FileManager.default.fileExists(atPath: current.path) ? try Data(contentsOf: current) : nil
    guard token(prior) == expected else { throw StoreError.conflict }
    if let prior {
      try prior.write(
        to: directory.appendingPathComponent("workspace.recovered-" + UUID().uuidString + ".json"),
        options: [.atomic])
    }
    try data.write(to: current, options: [.atomic])
    return (String(decoding: data, as: UTF8.self), token(data))
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
