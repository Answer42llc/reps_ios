import SwiftUI

// MARK: - Progress Indicator
struct OnboardingProgressBar: View {
    let progress: Double
    
    var body: some View {
        ProgressView(value: progress)
            .progressViewStyle(LinearProgressViewStyle(tint: .purple))
            .padding(.horizontal, 16)
    }
}

// MARK: - Capsule Border Button Style
struct CapsuleBorderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white)
            )
            .overlay(
                Capsule()
                    .stroke(Color.gray, lineWidth: 0.3)
            )
            .opacity(configuration.isPressed ? 0.5 : 1.0)
    }
}

// MARK: - Preset Button
struct OnboardingPresetButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(CapsuleBorderButtonStyle())
    }
}

// MARK: - Navigation Arrow Button
struct OnboardingArrowButton: View {
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(isEnabled ? .purple : Color(UIColor(.purple.opacity(0.5))))
        }
        .disabled(!isEnabled)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Continue Button
struct OnboardingContinueButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(isEnabled ? Color.purple : Color.gray))
                .cornerRadius(12)
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Custom Text Field
struct OnboardingTextField: View {
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        TextField(placeholder, text: $text)
            .font(.body)
    }
}



#Preview {
    OnboardingPresetButton(title: "aaaaa", action: {})
}
