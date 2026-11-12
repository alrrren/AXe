import ArgumentParser
import Foundation
import Testing
@testable import AXe

/// Slice B1: Siri Remote buttons on an Apple TV, and the rule that nothing else reaches one.
@Suite("Apple TV remote buttons")
struct AppleTVRemoteButtonTests {
    private static let simulator = "8775B9A0-A491-4182-88CD-43600178780F"

    private struct Usage: Equatable, CustomTestStringConvertible {
        let button: PhysicalDeviceButton
        let page: UInt64
        let code: UInt64
        var testDescription: String { "\(button) \(String(page, radix: 16))/\(String(code, radix: 16))" }
    }

    // Requirement: live probe on Sala (tvOS 27.2), b0-findings.md "Final mapping": Home 0x0C/0x40,
    // Menu 0x01/0x86, Select 0x01/0x89, Up 0x01/0x8C, Down 0x01/0x8D.
    // Requirement: B1 live check on Sala, 2026-11-12: Right (0x01/0x8A) moved focus Settings to FaceTime and
    // Left (0x01/0x8B) moved it back. Play/Pause is still unconfirmed, so it is deliberately absent.
    // Requirement: iPhone bytes stay as on main: Home 0x0C/0x40, Lock 0x0C/0x30, Siri 0x0C/0xCF.
    @Test(arguments: [
        Usage(button: .home, page: 0x0C, code: 0x40),
        Usage(button: .menu, page: 0x01, code: 0x86),
        Usage(button: .select, page: 0x01, code: 0x89),
        Usage(button: .up, page: 0x01, code: 0x8C),
        Usage(button: .down, page: 0x01, code: 0x8D),
        Usage(button: .left, page: 0x01, code: 0x8B),
        Usage(button: .right, page: 0x01, code: 0x8A),
        Usage(button: .lock, page: 0x0C, code: 0x30),
        Usage(button: .siri, page: 0x0C, code: 0xCF),
    ])
    private func buttonSendsItsProbedUsage(_ expected: Usage) {
        #expect(expected.button.usage.page == expected.page)
        #expect(expected.button.usage.code == expected.code)
    }

    private enum Family: Equatable { case appleTV, phone }

    private struct GateCase: CustomTestStringConvertible {
        let name: String
        let operation: PhysicalDeviceBrokerOperation
        /// The families that accept the operation.
        let accepted: Set<Family>
        var testDescription: String { name }
    }

    private static let remoteButtons: [PhysicalDeviceButton] = [.menu, .select, .up, .down, .left, .right, .playPause]

    private static let gateCases: [GateCase] = {
        let button = { (button: PhysicalDeviceButton) in
            PhysicalDeviceBrokerOperation.button(button, hold: 0, allowLock: true)
        }
        var cases = [
            GateCase(name: "keepAlive", operation: .keepAlive, accepted: [.appleTV, .phone]),
            GateCase(name: "home", operation: button(.home), accepted: [.appleTV, .phone]),
            GateCase(name: "lock", operation: button(.lock), accepted: [.phone]),
            GateCase(name: "siri", operation: button(.siri), accepted: [.phone]),
            GateCase(name: "display", operation: .display, accepted: [.phone]),
            GateCase(name: "touch", operation: .touch([], display: nil, allowPartial: false, deadlineUptime: nil),
                     accepted: [.phone]),
            // Requirement: B4 text entry, owner decision 2026-11-12. Keyboard input reaches an Apple TV as well.
            // Touch, display, rotate, tree and semanticPress stay phone-only.
            GateCase(name: "keys", operation: .keys([PhysicalKeyStep(code: 4, pressed: true)]),
                     accepted: [.appleTV, .phone]),
            GateCase(name: "rotate", operation: .rotate(.left, timeout: 1), accepted: [.phone]),
            GateCase(name: "tree", operation: .tree(timeout: 1), accepted: [.phone]),
            GateCase(name: "semanticPress", operation: .semanticPress(identifier: "switch"), accepted: [.phone]),
        ]
        cases += remoteButtons.map { GateCase(name: "\($0)", operation: button($0), accepted: [.appleTV]) }
        return cases
    }()

    // Requirement: Aleks's rule, no input other than remote buttons and keyboard keys reaches the Apple TV. A phone
    // or tablet has no remote, so the remote buttons are refused there. Home is the one button both accept.
    @Test(arguments: gateCases)
    private func deviceFamilyGate(_ gate: GateCase) {
        for family in [Family.appleTV, .phone] {
            do {
                try gate.operation.requireSupported(onAppleTV: family == .appleTV)
                #expect(gate.accepted.contains(family), "\(gate.name) reached \(family)")
            } catch let failure as CLIOutputFailure {
                #expect(!gate.accepted.contains(family), "\(gate.name) refused on \(family)")
                #expect(failure.code == "unsupportedOnDevice")
            } catch {
                Issue.record("\(gate.name) on \(family) threw \(error)")
            }
        }
    }

    // Requirement: a simulator has no remote, so `axe button menu --udid <simulator>` is refused.
    // ArgumentParser wraps whatever `validate()` throws into its own error, which hides the failure code
    // from `parse`. So the code is read from `validate()` on a command re-pointed at the simulator.
    @Test(arguments: ["menu", "select", "up", "down", "left", "right", "play-pause"])
    @MainActor
    func simulatorRefusesRemoteButtons(_ name: String) throws {
        #expect(throws: (any Error).self) { try Button.parse([name, "--udid", Self.simulator]) }

        var button = try Button.parse([name, "--udid", "00000001-0000000000000001"])
        button.simulatorUDID = Self.simulator
        do {
            try button.validate()
            Issue.record("button \(name) validated for a simulator")
        } catch let failure as CLIOutputFailure {
            #expect(failure.code == "unsupportedOnDevice")
        }

        // A phone button on the same simulator still parses, so the refusal is specific to the remote.
        _ = try Button.parse(["home", "--udid", Self.simulator])
    }
}
