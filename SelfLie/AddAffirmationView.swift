import SwiftUI
import CoreData
import Combine

struct AddAffirmationView: View {
    @Environment(NavigationCoordinator.self) private var navigationCoordinator
    @State private var affirmationText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    private var isValidInput: Bool {
        affirmationText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }
    
    var body: some View {
        VStack(spacing: 24) {
            headerView
            
            textInputSection
            
            guidanceSection
            
            Spacer()
        }
        .padding()
        .navigationTitle("Add a lie to yourself")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    navigationCoordinator.goBack()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Next") {
                    navigationCoordinator.navigateToRecording(text: affirmationText)
                }
                .disabled(!isValidInput)
                .foregroundColor(isValidInput ? .purple : .gray)
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Create Your Affirmation")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Write a positive statement about yourself")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type a lie you will listen to yourself")
                .font(.headline)
                .foregroundColor(.primary)
            
            TextEditor(text: $affirmationText)
                .focused($isTextFieldFocused)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isTextFieldFocused ? Color.purple : Color.clear, lineWidth: 2)
                )
            
            HStack {
                Spacer()
                Text("\(affirmationText.count) characters")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips for effective affirmations:")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                guidanceTip("Start with 'I am' or 'I never'")
                guidanceTip("Use present tense, as if it's already true")
                guidanceTip("Keep it personal and meaningful to you")
                guidanceTip("Make it specific and clear")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func guidanceTip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        AddAffirmationView()
    }
}