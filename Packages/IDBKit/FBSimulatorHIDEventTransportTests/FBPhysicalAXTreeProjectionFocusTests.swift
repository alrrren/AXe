import Foundation
import Testing
@testable import FBSimulatorControl

@Suite("Physical device focus projection")
struct FBPhysicalAXTreeProjectionFocusTests {
  // B3b: physical describe-ui must identify Sala's highlighted Search tile (2026-11-12 capture).
  @Test func salaSearchIsTheOnlyFocusedElement() throws {
    try FBSimulatorControlFrameworkLoader.accessibilityFrameworks.loadPrivateFrameworks(nil)
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/SalaFocusedSearch.plist")
    let fixture = try PropertyListDecoder().decode(Capture.self, from: Data(contentsOf: url))
    let entries = fixture.entries.map {
      FBPhysicalAXTreeProjection.Entry(requestType: $0.requestType, pid: $0.pid,
        objectID: $0.objectID, attribute: $0.attribute)
    }
    let json = try FBPhysicalAXTreeProjection.json(archive: fixture.archive, entries: entries)
    let roots = try JSONDecoder().decode([Node].self, from: json)
    let nodes = roots.flatMap(\.allNodes)
    let matches = nodes.filter { $0.AXLabel == "Search" }
    #expect(matches.count == 1)
    let search = try #require(matches.first)
    #expect(search.focused == true)
    // Only the highlighted tile may be true; omitted focus is valid for other elements.
    #expect(nodes.filter { $0.AXLabel != "Search" }.allSatisfy { $0.focused != true })
  }

  private struct Capture: Decodable {
    let archive: Data
    let entries: [Entry]

    struct Entry: Decodable {
      let requestType: UInt64
      let pid: Int32?
      let objectID: UInt64?
      let attribute: UInt64
    }
  }

  private struct Node: Decodable {
    let AXLabel: String?
    let focused: Bool?
    let children: [Node]?

    var allNodes: [Node] { [self] + (children ?? []).flatMap(\.allNodes) }
  }
}
