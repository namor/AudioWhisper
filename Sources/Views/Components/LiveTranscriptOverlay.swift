import SwiftUI

/// Semi-transparent frosted-glass overlay showing the last 2 lines of live
/// transcription text, rolling upward as new words arrive.
internal struct LiveTranscriptOverlay: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(.primary.opacity(0.85))
            .lineLimit(2)
            .truncationMode(.head)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .contentTransition(.numericText(countsDown: false))
            .animation(.easeOut(duration: 0.15), value: text)
    }
}
