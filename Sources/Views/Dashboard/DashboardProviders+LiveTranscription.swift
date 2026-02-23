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
            Label("Uses Parakeet TDT v3 (~600 MB). Model downloads automatically on first use.",
                  systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .appleSpeech:
            Label("Uses Apple SpeechAnalyzer. Requires macOS 26 or later.",
                  systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .off:
            EmptyView()
        }
    }
}
