import Foundation

@main struct Compatibility {
  static func main() throws {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let data = try Data(contentsOf: url)
    let decoded = try WorkspaceCodec.decode(data)
    let encoded = try WorkspaceCodec.encode(decoded)
    let before = try JSONSerialization.jsonObject(with: data) as! NSDictionary
    let after = try JSONSerialization.jsonObject(with: encoded) as! NSDictionary
    guard before == after else {
      throw RuleError("Legacy JSON fields changed during native round trip")
    }
    print(
      "PASS existing workspace: native round-trip preserves every JSON field, \(decoded.spaces.count) spaces"
    )
  }
}
