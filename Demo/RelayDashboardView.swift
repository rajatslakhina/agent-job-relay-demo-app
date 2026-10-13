import SwiftUI
import AgentJobRelay

struct RelayDashboardView: View {
    @Bindable var model: RelayDemoModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    controls
                    if let snapshot = model.snapshot {
                        SummaryCard(snapshot: snapshot, lastEvent: model.lastEvent)
                        if snapshot.jobs.isEmpty {
                            ContentUnavailableView("Submitting jobs…", systemImage: "paperplane",
                                                   description: Text("Idempotency keys are persisted before the first attempt."))
                        } else {
                            ForEach(snapshot.jobs) { job in
                                JobCard(job: job) { model.cancel(job.id) }
                            }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Agent Job Relay")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await model.onAppear() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Stream", selection: $model.selectedProfile) {
                ForEach(ChaosProfile.all, id: \.self) { profile in
                    Text(profile.name).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("profilePicker")

            HStack(spacing: 8) {
                Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                    model.isPlaying ? model.pause() : model.play()
                }
                .buttonStyle(.borderedProminent)
                Button("Step", systemImage: "forward.frame") { model.step() }
                    .buttonStyle(.bordered)
                Button("Kill & relaunch", systemImage: "arrow.counterclockwise.circle") { model.killAndRelaunch() }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                Spacer(minLength: 0)
                Button("Reset", systemImage: "gobackward") { model.reset() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
            }
            .font(.footnote.weight(.semibold))
            .labelStyle(.titleAndIcon)
        }
    }
}

private struct SummaryCard: View {
    let snapshot: SimulationSnapshot
    let lastEvent: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                convergenceBadge
                Spacer()
                Text(verbatim: "tick \(snapshot.tick)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Metric(label: "Submit calls → jobs",
                           value: "\(snapshot.server.submitCalls) → \(snapshot.server.jobsCreated)",
                           note: snapshot.server.lostAcks > 0 ? "\(snapshot.server.lostAcks) lost ack, no duplicate job" : nil)
                    Metric(label: "Backfill fetches", value: "\(snapshot.health.backfillFetches)",
                           note: snapshot.health.coalescedReconciles > 0 ? "\(snapshot.health.coalescedReconciles) coalesced" : nil)
                }
                GridRow {
                    Metric(label: "Relaunches", value: "\(snapshot.relaunches)", note: nil)
                    Metric(label: "Auto-cancels (budget)", value: "\(snapshot.health.autoCancels)", note: nil)
                }
            }
            Text(lastEvent).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var convergenceBadge: some View {
        let behind = snapshot.jobs.reduce(UInt64(0)) { $0 &+ $1.lag }
        if snapshot.isFinished && snapshot.allConverged {
            Label(String("All \(snapshot.jobs.count) jobs match the server log"), systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.subheadline.weight(.semibold))
        } else if snapshot.isFinished {
            Label("Diverged from server log", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline.weight(.semibold))
        } else {
            Label(String("\(snapshot.profile.name) stream · \(behind) events behind the server"),
                  systemImage: "antenna.radiowaves.left.and.right")
                .font(.subheadline.weight(.semibold))
        }
    }
}

private struct Metric: View {
    let label: String
    let value: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

private struct JobCard: View {
    let job: SimulatedJob
    let onCancel: () -> Void

    private static let phaseNames = ["Planning", "Researching", "Drafting", "Reviewing"]

    var body: some View {
        let state = job.projection.state
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.prompt.isEmpty ? "Untitled job" : job.prompt).font(.headline)
                    Text(verbatim: "\(job.id.rawValue) · applied \(state.appliedThrough) of \(job.serverHighWater) server events")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: job.projection.status)
            }

            PhaseTrack(current: state.phase?.ordinal, names: Self.phaseNames)

            if case .failed(let reason) = job.projection.status {
                Label(reason, systemImage: "xmark.octagon").font(.caption).foregroundStyle(.red)
            }

            HStack {
                Label(String("\(state.tokensUsed.formatted()) tokens"), systemImage: "gauge.with.dots.needle.33percent")
                if job.tokenBudget > 0 {
                    Text(verbatim: "budget \(job.tokenBudget.formatted())")
                        .foregroundStyle(state.tokensUsed >= job.tokenBudget ? Color.orange : Color.secondary)
                }
                Spacer()
                if case .running = job.projection.status {
                    Button("Cancel", role: .destructive, action: onCancel)
                        .buttonStyle(.bordered).controlSize(.mini)
                }
            }
            .font(.caption)

            if state.artifacts.isEmpty {
                Text("No results yet").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(state.artifacts, id: \.id) { artifact in
                    ArtifactRow(artifact: artifact)
                }
            }

            LedgerRow(ledger: job.projection.ledger, buffered: job.projection.bufferedCount,
                      converged: job.serverTerminal && job.projection.isTerminal ? job.converged : nil)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PhaseTrack: View {
    let current: Int?
    let names: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                let reached = (current ?? -1) >= index
                VStack(spacing: 3) {
                    Capsule().fill(reached ? Color.accentColor : Color.secondary.opacity(0.25)).frame(height: 4)
                    Text(name).font(.system(size: 9, weight: reached ? .semibold : .regular))
                        .foregroundStyle(reached ? Color.primary : Color.secondary)
                }
            }
        }
    }
}

private struct ArtifactRow: View {
    let artifact: Artifact

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            badge
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(artifact.id) · rev \(artifact.revision)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                Text(artifact.body).font(.footnote).italic(artifact.confidence != .final)
            }
        }
    }

    @ViewBuilder private var badge: some View {
        switch artifact.confidence {
        case .final:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .provisional:
            Image(systemName: "circle.dashed").foregroundStyle(.blue)
        case .unconfirmed:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        }
    }
}

private struct LedgerRow: View {
    let ledger: DeliveryLedger
    let buffered: Int
    /// nil while the job is still running on either side.
    let converged: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                cell("recv", ledger.received)
                cell("applied", ledger.applied)
                cell("dup", ledger.duplicates)
                cell("reordered", ledger.reordered)
                cell("backfill", ledger.appliedByChannel[.backfill] ?? 0)
                cell("buffered", buffered)
            }
            HStack(spacing: 6) {
                Image(systemName: ledger.isConserved(buffered: buffered) ? "equal.circle" : "exclamationmark.circle")
                Text(ledger.isConserved(buffered: buffered) ? "every delivery accounted for" : "ledger mismatch")
                if let converged {
                    Text("·")
                    Text(converged ? "matches server log" : "diverged").foregroundStyle(converged ? Color.green : Color.red)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cell(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: "\(value)").font(.caption.monospacedDigit().weight(.semibold))
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

private struct StatusPill: View {
    let status: JobStatus

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var title: String {
        switch status {
        case .running(let phase): return phase?.name ?? "Queued"
        case .cancelling: return "Cancelling…"
        case .completed: return "Completed"
        case .completedBeforeCancel: return "Finished before cancel"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var color: Color {
        switch status {
        case .running: return .blue
        case .cancelling, .completedBeforeCancel: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}
