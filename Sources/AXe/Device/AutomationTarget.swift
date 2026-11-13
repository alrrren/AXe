import Foundation
import FBSimulatorControl

enum AutomationTarget {
    case simulator(FBSimulator)
    case device(CoreDevice)

    // A physical hardware UDID has a different shape from a simulator UUID.
    // Keep CoreDevice discovery off the simulator input path.
    static func isPhysicalInputUDID(_ udid: String) -> Bool {
        let bytes = udid.utf8
        func isHex(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
        switch bytes.count {
        case 25:
            let separator = bytes.index(bytes.startIndex, offsetBy: 8)
            return bytes[separator] == 45 && bytes[..<separator].allSatisfy(isHex)
                && bytes[bytes.index(after: separator)...].allSatisfy(isHex)
        case 40:
            return bytes.allSatisfy(isHex)
        default:
            return false
        }
    }

    /// The device for a broker-backed command: only its UDID. The broker resolves the CoreDevice record
    /// itself, reports `targetNotFound` through the lease, and reads readiness when a lease needs it
    /// (`PhysicalLockRecheck`), so the CLI spawns no inventory read (0.65-1.1 s). Commands that need the full
    /// record use `physicalDeviceRecord`.
    static func physicalInputDevice(udid: String) async throws -> CoreDevice? {
        guard isPhysicalInputUDID(udid) else { return nil }
        return CoreDevice(identifier: udid, udid: udid, name: nil, model: nil, osVersion: nil,
            tunnelAddress: nil, tunnelConnected: nil, transport: nil, paired: nil,
            developerModeEnabled: nil, developerDiskImageMounted: nil, coreDeviceVersion: nil)
    }

    /// The full CoreDevice record for a hardware UDID or a CoreDevice UUID, read from the inventory.
    /// A UUID has a simulator UUID's shape and devicectl accepts it for any paired device, so only the
    /// inventory (which lists no simulators) tells them apart: a UUID it does not list returns nil.
    static func physicalDeviceRecord(udid: String, allowingAppleTV: Bool = false) async throws -> CoreDevice? {
        let isHardwareUDID = isPhysicalInputUDID(udid)
        let uuid = UUID(uuidString: udid)
        guard isHardwareUDID || uuid != nil else { return nil }
        // devicectl costs 0.2-0.7 s and a simulator call must stay as fast as the latest release
        // (AGENTS.md, Performance), so a directory in the default device set skips the inventory.
        if let uuid, isSimulatorInDefaultSet(uuid) { return nil }
        guard let device = try await CoreDeviceInventory.list().first(where: { $0.matches(udid) }) else {
            guard isHardwareUDID else { return nil }
            throw CLIOutputFailure(code: "targetNotFound",
                message: "No physical device matches the hardware UDID. Run axe list-devices.")
        }
        // The input broker, video recording and streaming, and settings look the device up here, so this is the
        // one place that keeps an Apple TV, which list-devices shows, from being driven. The broker passes
        // `allowingAppleTV` and then admits remote buttons, keyboard input, semantic press and tree reads; record-video and
        // stream-video pass it because they only read the screen. doctor and screenshot use `resolve` instead.
        if device.isAppleTV, !allowingAppleTV {
            throw unsupportedOnDevice("AXe supports only list-devices, doctor, screenshot, record-video, stream-video, describe-ui, tap --semantic-press, axe button and keyboard input on an Apple TV.")
        }
        return device
    }

    /// AXe only uses the default device set; a simulator outside it still reaches the inventory, which lists none.
    private static func isSimulatorInDefaultSet(_ uuid: UUID) -> Bool {
        let devices = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
        return FileManager.default.fileExists(atPath: devices.appendingPathComponent(uuid.uuidString).path)
    }

    /// Refuses a simulator-only command for a physical device's hardware UDID, before any work.
    static func refuseOnDevice(_ udid: String, _ message: String) throws {
        if isPhysicalInputUDID(udid) { throw unsupportedOnDevice(message) }
    }

    static func unsupportedOnDevice(_ message: String) -> CLIOutputFailure {
        CLIOutputFailure(code: "unsupportedOnDevice", message: message)
    }

    @MainActor
    static func resolve(udid: String) async throws -> Self {
        let identifier = udid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            throw CLIOutputFailure(code: "invalidArguments", message: "Supply a simulator or device UDID.")
        }

        let logger = AxeLogger()
        try await performGlobalSetup(logger: logger)
        let set = try await getSimulatorSet(deviceSetPath: nil, logger: logger,
                                            reporter: EmptyEventReporter.shared)
        if let simulator = set.allSimulators.first(where: { $0.udid.caseInsensitiveCompare(identifier) == .orderedSame }) {
            return .simulator(simulator)
        }

        if let device = try await CoreDeviceInventory.list().first(where: { $0.matches(identifier) }) {
            return .device(device)
        }
        throw CLIOutputFailure(code: "targetNotFound",
            message: "No simulator or physical device matches UDID \(identifier). Run axe list-simulators or axe list-devices.")
    }
}

extension Duration {
    /// Seconds as a `TimeInterval`, for socket and service timeouts.
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
