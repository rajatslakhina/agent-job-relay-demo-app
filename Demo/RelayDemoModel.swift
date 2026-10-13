import Foundation
import Observation
import AgentJobRelay

/// Drives a `RelaySimulation` tick by tick and publishes snapshots to SwiftUI.
///
/// Every async continuation re-checks `runID` after each `await`. A Reset or profile change
/// bumps it, so work still finishing on the *previous* simulation can never write its
/// snapshot or status line over the new run. Ordering between steps, kills and cancels on
/// the *same* run is the library's job: `RelaySimulation` serialises them with a FIFO lock.
@MainActor
@Observable
final class RelayDemoModel {
    private(set) var configuration: DemoConfiguration
    private(set) var snapshot: SimulationSnapshot?
    private(set) var isPlaying = false
    private(set) var lastEvent = "Ready"

    private var simulation: RelaySimulation
    private var runID = 0
    private var playTask: Task<Void, Never>?

    init(configuration: DemoConfiguration) {
        self.configuration = configuration
        self.simulation = Self.makeSimulation(configuration)
    }

    private static func makeSimulation(_ configuration: DemoConfiguration) -> RelaySimulation {
        RelaySimulation(profile: configuration.profile, seed: configuration.seed,
                        eventsPerTick: configuration.eventsPerTick)
    }

    var profile: ChaosProfile { configuration.profile }

    /// Picker binding. Changing the stream restarts the run.
    var selectedProfile: ChaosProfile {
        get { configuration.profile }
        set { select(profile: newValue) }
    }

    func onAppear() async {
        let run = runID
        await refresh(run: run)
        if configuration.autoplay, run == runID, snapshot?.isFinished != true { play() }
    }

    func select(profile: ChaosProfile) {
        guard profile != configuration.profile else { return }
        configuration.profile = profile
        reset(autoplay: true)
    }

    func reset(autoplay: Bool = false) {
        pause()
        runID += 1
        let run = runID
        simulation = Self.makeSimulation(configuration)
        snapshot = nil
        lastEvent = "Reset — \(configuration.profile.name) stream, seed \(configuration.seed)"
        Task {
            await refresh(run: run)
            if autoplay, run == runID { play() }
        }
    }

    func play() {
        guard playTask == nil else { return }
        isPlaying = true
        let run = runID
        let simulation = simulation
        let interval = configuration.tickInterval
        playTask = Task { [weak self] in
            while !Task.isCancelled {
                await simulation.step()
                guard let self, self.runID == run, !Task.isCancelled else { return }
                await self.refresh(run: run)
                if self.serverDone {
                    await simulation.finish()
                    guard self.runID == run else { return }
                    await self.refresh(run: run)
                    if self.runID == run {
                        self.lastEvent = "Server finished — final push sent, relay reconciled"
                    }
                    break
                }
                try? await Task.sleep(for: interval)
            }
            guard let self, self.runID == run, !Task.isCancelled else { return }
            self.playTask = nil
            self.isPlaying = false
        }
    }

    func pause() {
        playTask?.cancel()
        playTask = nil
        isPlaying = false
    }

    func step() {
        pause()
        let run = runID
        let simulation = simulation
        Task {
            await simulation.step()
            guard run == runID else { return }
            await refresh(run: run)
            if run == runID { lastEvent = "Stepped one tick" }
        }
    }

    /// Does not touch the play loop: the simulation queues the kill between two steps.
    func killAndRelaunch() {
        let run = runID
        let simulation = simulation
        Task {
            await simulation.killAndRelaunch()
            guard run == runID else { return }
            await refresh(run: run)
            if run == runID {
                lastEvent = "App killed: in-flight stream lost. Relaunched from checkpoint and caught up."
            }
        }
    }

    func cancel(_ id: JobID) {
        let run = runID
        let simulation = simulation
        Task {
            await simulation.cancel(id)
            guard run == runID else { return }
            await refresh(run: run)
            if run == runID { lastEvent = "Cancel requested for \(id.rawValue) — the server decides the outcome" }
        }
    }

    private var serverDone: Bool {
        guard let jobs = snapshot?.jobs, !jobs.isEmpty else { return false }
        return jobs.allSatisfy(\.serverTerminal)
    }

    /// Reads the snapshot of the simulation that belongs to `run`, and publishes it only if
    /// that run is still current when the read completes.
    private func refresh(run: Int) async {
        guard run == runID else { return }
        let simulation = simulation
        let next = await simulation.snapshot()
        guard run == runID else { return }
        snapshot = next
    }
}
