import SwiftUI

internal extension DashboardProvidersView {
    var liveTranscriptionSection: some View {
        Group {
            Picker("Engine", selection: $liveTranscriptionProvider) {
                ForEach(LiveTranscriptionProvider.availableProviders, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            if liveTranscriptionProvider != .off {
                liveTranscriptionInfo
            }
        }
    }

    @ViewBuilder
    private var liveTranscriptionInfo: some View {
        switch liveTranscriptionProvider {
        case .fluidAudio:
            fluidAudioCard
        case .parakeetMLX:
            parakeetMLXCard
        case .appleSpeech:
            Label("Uses Apple SpeechAnalyzer. Requires macOS 26 or later.",
                  systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .off:
            EmptyView()
        }
    }

    @ViewBuilder
    private var fluidAudioCard: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            // Model info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DashboardTheme.Spacing.sm) {
                    Text("Parakeet TDT v3")
                        .font(DashboardTheme.Fonts.sans(14, weight: .medium))
                        .foregroundStyle(DashboardTheme.ink)
                    
                    Text("RECOMMENDED")
                        .font(DashboardTheme.Fonts.sans(9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DashboardTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                
                Text("Default streaming model, downloads automatically on first use")
                    .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)
            }
            
            Spacer()
            
            // Size
            Text("~600 MB")
                .font(DashboardTheme.Fonts.mono(11, weight: .regular))
                .foregroundStyle(DashboardTheme.inkMuted)
            
            // Status/Action
            Group {
                if fluidAudioModelManager.isDownloading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(fluidAudioModelManager.downloadProgress)
                            .font(DashboardTheme.Fonts.sans(10, weight: .medium))
                            .foregroundStyle(DashboardTheme.inkMuted)
                    }
                    .frame(minWidth: 80)
                } else if fluidAudioModelManager.isDownloaded {
                    HStack(spacing: 6) {
                        Text("Installed")
                            .font(DashboardTheme.Fonts.sans(10, weight: .medium))
                            .foregroundStyle(Color(red: 0.35, green: 0.60, blue: 0.40))
                        
                        Button {
                            Task { await fluidAudioModelManager.deleteModel() }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(DashboardTheme.inkMuted)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button("Get") {
                        Task { await fluidAudioModelManager.downloadModel() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, DashboardTheme.Spacing.md)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var parakeetMLXCard: some View {
        let repo = selectedParakeetModel.repoId
        let isDownloaded = mlxModelManager.downloadedModels.contains(repo)
        let isDownloading = mlxModelManager.isDownloading[repo] ?? false

        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            HStack(spacing: DashboardTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DashboardTheme.Spacing.sm) {
                        Text(selectedParakeetModel.displayName)
                            .font(DashboardTheme.Fonts.sans(14, weight: .medium))
                            .foregroundStyle(DashboardTheme.ink)

                        if selectedParakeetModel == .tdt1_1b {
                            Text("RECOMMENDED")
                                .font(DashboardTheme.Fonts.sans(9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DashboardTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    Text("Uses your selected Parakeet model • updates every ~5s")
                        .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                        .foregroundStyle(DashboardTheme.inkMuted)
                }

                Spacer()

                Text("~\(String(format: "%.1f", selectedParakeetModel.estimatedSizeGB)) GB")
                    .font(DashboardTheme.Fonts.mono(11, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)

                Group {
                    if isDownloading {
                        ProgressView().controlSize(.small)
                    } else if isDownloaded {
                        Text("Ready")
                            .font(DashboardTheme.Fonts.sans(10, weight: .medium))
                            .foregroundStyle(Color(red: 0.35, green: 0.60, blue: 0.40))
                    } else {
                        Button("Get") {
                            Task { await mlxModelManager.ensureParakeetModel() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            Label(
                "Shares model cache with Parakeet transcription engine — no extra download if already installed",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(DashboardTheme.Fonts.sans(11, weight: .regular))
            .foregroundStyle(DashboardTheme.inkMuted)
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, DashboardTheme.Spacing.md)
        .contentShape(Rectangle())
    }
}
