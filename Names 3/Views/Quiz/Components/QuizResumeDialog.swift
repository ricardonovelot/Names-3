import SwiftUI

struct QuizResumeDialog: View {
    let progress: String
    let onResume: () -> Void
    let onStartFresh: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            iconSection
            
            textSection
            
            actionButtons
        }
        .padding(28)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .padding(40)
    }
    
    @ViewBuilder
    private var iconSection: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 80, height: 80)
            
            Image(systemName: "arrow.circlepath")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.blue)
        }
    }
    
    @ViewBuilder
    private var textSection: some View {
        VStack(spacing: 12) {
            Text("Resume Quiz?")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            Text("You have an unfinished quiz session with \(progress). Would you like to continue where you left off?")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                onResume()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Resume Quiz")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            
            Button {
                onStartFresh()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Start Fresh")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}
