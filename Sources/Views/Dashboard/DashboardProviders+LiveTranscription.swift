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
}
