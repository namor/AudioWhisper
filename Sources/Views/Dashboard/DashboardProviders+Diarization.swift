import SwiftUI

internal extension DashboardProvidersView {
    var diarizationSection: some View {
        Group {
            if Arch.isAppleSilicon {
                Toggle(isOn: $diarizationEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable speaker diarization")
                        Text("Detect and label distinct speakers in recordings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if diarizationEnabled {
                    diarizationModelStatus

                    Picker("Number of Speakers", selection: $diarizationSpeakerCount) {
                        Text("Auto-detect").tag(0)
                        ForEach(2...10, id: \.self) { n in
                            Text("\(n) speakers").tag(n)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Set the exact speaker count for better accuracy, or leave on Auto.")

                    Label("Works with Local Whisper engine. Other engines coming soon.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } else {
                Label("Speaker diarization requires an Apple Silicon Mac.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var diarizationModelStatus: some View {
        LabeledContent("Models") {
            HStack(spacing: 10) {
                if isDiarizationPreparing {
                    ProgressView().controlSize(.small)
                    Text("Preparing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isDiarizationReady {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color(nsColor: .systemGreen))
                } else {
                    Button("Download Models") {
                        downloadDiarizationModels()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }

        if let msg = diarizationStatusMessage {
            Text(msg)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func downloadDiarizationModels() {
        isDiarizationPreparing = true
        diarizationStatusMessage = "Downloading diarization models…"
        Task {
            do {
                try await sharedDiarizationService.prepareModels()
                await MainActor.run {
                    isDiarizationReady = true
                    isDiarizationPreparing = false
                    diarizationStatusMessage = nil
                }
            } catch {
                await MainActor.run {
                    isDiarizationPreparing = false
                    diarizationStatusMessage = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
