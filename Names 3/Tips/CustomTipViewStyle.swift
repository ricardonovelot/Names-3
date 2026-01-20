import SwiftUI
import TipKit

struct CustomTipViewStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = configuration.image {
                image
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                configuration.title
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if let message = configuration.message {
                    message
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                if !configuration.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(configuration.actions) { action in
                            Button(action: action.handler) {
                                action.label()
                                    .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}