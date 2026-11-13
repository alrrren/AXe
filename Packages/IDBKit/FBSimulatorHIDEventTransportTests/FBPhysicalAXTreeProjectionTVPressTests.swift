import Foundation
import Testing
@testable import FBSimulatorControl

@Suite("Apple TV semantic press selection")
struct FBPhysicalAXTreeProjectionTVPressTests {
  // Sala's Home tree (2026-11-12 capture). Every Home tile shares AXUniqueId "AppCell"; live runs on
  // 2026-11-13 matched 30 of them by id and exactly one by label "Search" (Search tile x686 y750 w250 h150).
  private static let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

  private func prepare(identifier: String?, label: String?) throws -> FBPhysicalAXTreeProjection.PreparedPress {
    try FBSimulatorControlFrameworkLoader.accessibilityFrameworks.loadPrivateFrameworks(nil)
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/SalaFocusedSearch.plist")
    let fixture = try PropertyListDecoder().decode(Capture.self, from: Data(contentsOf: url))
    let entries = fixture.entries.map {
      FBPhysicalAXTreeProjection.Entry(requestType: $0.requestType, pid: $0.pid,
        objectID: $0.objectID, attribute: $0.attribute)
    }
    return try FBPhysicalAXTreeProjection.prepareTVPress(archive: fixture.archive, entries: entries,
      identifier: identifier, label: label, displayBounds: Self.display)
  }

  // Live defect evidence: selecting the shared id "AppCell" must be refused as ambiguous, so no action request exists.
  @Test func sharedAppCellIdentifierIsRefusedAsAmbiguous() throws {
    let error = try #require(throws: Error.self) { try prepare(identifier: "AppCell", label: nil) }
    #expect(error.localizedDescription.contains("matched 30 elements"))
  }

  // Live defect evidence: the exact label "Search" selects exactly one tile, and an Apple TV press carries no checkbox value.
  @Test func exactSearchLabelSelectsOneTileWithoutCheckboxValue() throws {
    let press = try prepare(identifier: nil, label: "Search")
    #expect(press.target.identifier == "AppCell")
    #expect(press.target.frame == CGRect(x: 686, y: 750, width: 250, height: 150))
    #expect(press.target.value == nil)
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
}
