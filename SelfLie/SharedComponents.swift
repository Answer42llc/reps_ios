import SwiftUI

// MARK: - Highlighted Affirmation Text Component
struct HighlightedAffirmationText: View {
    let text: String
    let highlightedWordIndices: Set<Int>
    
    var body: some View {
        let words = text.components(separatedBy: " ")
        
        Text(buildAttributedString(words: words))
            .font(.title)
            .fontWeight(.medium)
            .multilineTextAlignment(.center)
    }
    
    private func buildAttributedString(words: [String]) -> AttributedString {
        var result = AttributedString()
        
        for (index, word) in words.enumerated() {
            var attributedWord = AttributedString(word)
            
            if highlightedWordIndices.contains(index) {
                attributedWord.foregroundColor = .purple
            } else {
                attributedWord.foregroundColor = .primary
            }
            
            result.append(attributedWord)
            
            // Add space between words (except for the last word)
            if index < words.count - 1 {
                result.append(AttributedString(" "))
            }
        }
        
        return result
    }
}

// MARK: - Onboarding Affirmation Card View
struct OnboardingAffirmationCard: View {
    let text: String
    let highlightedWordIndices: Set<Int>
    
    var body: some View {
        VStack {
            HighlightedAffirmationText(
                text: text,
                highlightedWordIndices: highlightedWordIndices
            )
            .font(.title2)
            .fontWeight(.regular)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
}

// MARK: - Recording Button Component
struct RecordingButton: View {
    let isRecording: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.purple)
                
                Text(isRecording ? "Tap to stop" : "Tap to record")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Loading Indicator
struct LoadingIndicator: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                .scaleEffect(2.0)
        }
    }
}

// MARK: - Success Indicator
struct SuccessIndicator: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 60))
            .foregroundColor(.purple)
    }
}

// MARK: - Retry Button
struct RetryButton: View {
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Button(action: action) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.purple)
                    .font(.system(size: 80))
            }
            .foregroundStyle(Color(.secondarySystemBackground))
            .buttonStyle(PlainButtonStyle())
        }
    }
}

// MARK: - Practice Card View (from PracticeView)
struct PracticeCardView<StatusContent: View, MainContent: View, ActionContent: View>: View {
    @ViewBuilder let statusContent: StatusContent
    @ViewBuilder let mainContent: MainContent
    @ViewBuilder let actionContent: ActionContent
    let showActionArea: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Card content
            VStack(spacing: 24) {
                // Status area
                statusContent
                
                // Content area
                mainContent
                
                // Action area (inside card)
                if showActionArea {
                    actionContent
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)  // Ensure full width
        }
        .background(Color.white)
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Practice Status Area Components
struct PracticeStatusPill: View {
    let text: String
    
    var body: some View {
        Text(text)
            .fontDesign(.default)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(.purple))
            .cornerRadius(12)
    }
}

struct PracticeSuccessStatus: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .font(.headline)
        .fontDesign(.default)
        .foregroundColor(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Capsule().fill(.purple))
        .cornerRadius(12)
    }
}

struct PracticeFailureStatus: View {
    var body: some View {
        Label{
            Text("Try Again")
        } icon: {
            Image(systemName: "xmark")
        }
        .foregroundStyle(.secondary)
        .fontWeight(.semibold)
        .fontDesign(.default)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - Practice Card Action Button
struct PracticeCardActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .fontDesign(.default)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .foregroundStyle(.purple)
        .clipShape(Capsule())
    }
}


#Preview {
    PracticeStatusPill(text: "ddddddddd")
    PracticeSuccessStatus()
}
