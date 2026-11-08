import Testing
@testable import Ajour

/// Holding a downloaded update until Ajour is quiet, or the user asks for it.
@MainActor
struct PendingUpdateInstallTests {
    final class Recorder {
        var installCount = 0
        var isQuiet = false
    }

    let recorder = Recorder()

    func makePendingInstall() -> PendingUpdateInstall {
        let recorder = recorder
        return PendingUpdateInstall(isQuiet: { recorder.isQuiet })
    }

    func scheduleCountingInstall(on pending: PendingUpdateInstall) {
        let recorder = recorder
        pending.schedule { recorder.installCount += 1 }
    }

    @Test func evaluateWithoutScheduleDoesNothing() {
        recorder.isQuiet = true
        let pending = makePendingInstall()

        pending.evaluate()

        #expect(!pending.isScheduled)
        #expect(!pending.isInstalling)
        #expect(recorder.installCount == 0)
    }

    @Test func evaluateWhileNotQuietKeepsTheInstallPending() {
        let pending = makePendingInstall()
        scheduleCountingInstall(on: pending)

        pending.evaluate()

        #expect(recorder.installCount == 0)
        #expect(pending.isScheduled)
    }

    @Test func evaluateWhenQuietInstallsOnce() {
        let pending = makePendingInstall()
        scheduleCountingInstall(on: pending)
        recorder.isQuiet = true

        pending.evaluate()
        pending.evaluate()

        #expect(recorder.installCount == 1)
        #expect(pending.isInstalling)
    }

    @Test func installNowInstallsEvenWhenNotQuiet() {
        let pending = makePendingInstall()
        scheduleCountingInstall(on: pending)

        pending.installNow()

        #expect(recorder.installCount == 1)
        #expect(pending.isInstalling)
    }

    @Test func scheduledInstallDoesNotMarkARelaunch() {
        let pending = makePendingInstall()

        scheduleCountingInstall(on: pending)

        #expect(!pending.isInstalling)
    }

    @Test func cancelDropsThePendingInstall() {
        let pending = makePendingInstall()
        scheduleCountingInstall(on: pending)

        pending.cancel()
        recorder.isQuiet = true
        pending.evaluate()

        #expect(!pending.isScheduled)
        #expect(recorder.installCount == 0)
    }
}
