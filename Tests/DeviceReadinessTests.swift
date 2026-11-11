import Testing
@testable import AXe

// Requirement (Aleks): "report lock as not checked" for the Apple TV in `axe doctor`, so doctor
// gives a clear verdict on an Apple TV instead of failing on its unavailable lock state.

@Suite("Device readiness")
struct DeviceReadinessTests {
    private static func readiness(_ checks: [ReadinessCheck]) -> TargetReadiness {
        TargetReadiness(target: "device", udid: "00000009-0000000000000009", name: "Test device", checks: checks)
    }

    private static let ready = ReadinessCheck("notPaired", observed: true, fix: "")
    private static let notChecked = ReadinessCheck("deviceLocked", notChecked: "skipped")

    // Aleks: "report lock as not checked": a skipped check must not fail the verdict.
    @Test("A device whose only non-ready check is notChecked is ready")
    func notCheckedIsReady() {
        let report = Self.readiness([Self.ready, Self.notChecked])
        #expect(report.checks.map(\.status) == [.ready, .notChecked])
        #expect(report.ready)
    }

    // Aleks: "report lock as not checked": only the skipped check is exempt; real blockers still fail.
    @Test("A blocked or unchecked check still makes the device not ready, next to a notChecked one",
          arguments: [
              ReadinessCheck("developerModeDisabled", observed: false, fix: ""),
              ReadinessCheck("developerModeDisabled", observed: nil, fix: ""),
          ])
    func otherStatusesStillFail(_ failing: ReadinessCheck) {
        #expect(!Self.readiness([Self.ready, Self.notChecked, failing]).ready)
    }

    // Aleks: "report lock as not checked" for the Apple TV; iPhone and iPad keep the real lock check.
    @Test("An Apple TV reports deviceLocked as notChecked from its list record alone")
    func appleTVLockNotChecked() async throws {
        // No tunnel address, so doctor stops before any device connection. An Apple TV that wrongly
        // went through `devicectl device info details` would throw here instead of returning.
        let appleTV = CoreDevice(identifier: "77777777-7777-4777-8777-777777777777",
            udid: "00000007-0000000000000007", name: "Test Apple TV", model: "AppleTV14,1", osVersion: "27.0",
            tunnelAddress: nil, tunnelConnected: nil, transport: "localNetwork", paired: true,
            developerModeEnabled: true, developerDiskImageMounted: true, coreDeviceVersion: "689.2",
            isAppleTV: true)

        let inspection = try await DeviceInspection.inspect(appleTV)

        let lock = try #require(inspection.report.checks.first { $0.id == "deviceLocked" })
        #expect(lock.status == .notChecked)
        // The unreachable tunnel is still the verdict: notChecked hides nothing else.
        #expect(inspection.report.checks.first { $0.id == "deviceNotConnected" }?.status == .blocked)
        #expect(!inspection.report.ready)
    }
}
