import SwiftUI

/// Scrolling overlay that shows live transcription text during recording.
internal struct LiveTranscriptOverlay: View {
    let text: String

    @Namespace private var bottomAnchor

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .id("liveTextBottom")
            }
            .frame(maxHeight: 100)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
            )
            .onChange(of: text) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("liveTextBottom", anchor: .bottom)
                }
            }
        }
    }
}
