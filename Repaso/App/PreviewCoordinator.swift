import Foundation
import Observation
import RepasoCore

/// Grants live-preview slots (at most 4 at once) and turns previews off in Low Power Mode, under Reduce Motion,
/// while a list is flick-scrolling, or with the `-noLivePreviews` launch argument.
@Observable @MainActor
final class PreviewCoordinator {
    private var budget = PreviewBudget<UUID>(capacity: 4)
    private var scrollingFast = false
    private var reduceMotion = false
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private let disabledByLaunch = ProcessInfo.processInfo.arguments.contains("-noLivePreviews")
    @ObservationIgnored private var powerObserver: NSObjectProtocol?

    init() {
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.update()
            }
        }
        update()
    }

    func isGranted(_ id: UUID) -> Bool { budget.isGranted(id) }
    func request(_ id: UUID) { budget.request(id) }
    func release(_ id: UUID) { budget.release(id) }

    func setScrolling(fast: Bool) {
        guard fast != scrollingFast else { return }
        scrollingFast = fast
        update()
    }

    func setReduceMotion(_ on: Bool) {
        reduceMotion = on
        update()
    }

    private func update() {
        budget.setEnabled(!(disabledByLaunch || lowPower || reduceMotion || scrollingFast))
    }
}
