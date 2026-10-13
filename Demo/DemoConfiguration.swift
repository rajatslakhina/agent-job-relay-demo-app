import AgentJobRelay

/// The app owns the run configuration the library's simulation takes as input.
struct DemoConfiguration: Equatable {
    var profile: ChaosProfile
    var seed: UInt64
    var autoplay: Bool
    /// One server event per tick and a 700 ms tick: a run lasts about 13 seconds (18 ticks), long
    /// enough to press Cancel or Kill & relaunch while jobs are still running.
    var eventsPerTick = 1
    var tickInterval: Duration = .milliseconds(700)

    static let standard = DemoConfiguration(profile: .flaky, seed: 2026, autoplay: true)

    static func fromLaunchArguments(_ arguments: [String]) -> DemoConfiguration {
        var configuration = standard
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let name = value(after: "-profile")?.lowercased(),
           let profile = ChaosProfile.all.first(where: { $0.name.lowercased() == name }) {
            configuration.profile = profile
        }
        if let raw = value(after: "-seed"), let seed = UInt64(raw) {
            configuration.seed = seed
        }
        if arguments.contains("-paused") { configuration.autoplay = false }
        return configuration
    }
}
