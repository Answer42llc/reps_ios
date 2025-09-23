import SwiftUI

struct OnboardingIntroView: View {
    struct IntroPage: Identifiable {
        let id = UUID()
        let imageName: String
        var darkImageName: String? = nil
        let message: String
        let buttonTitle: String
        let imageScale: CGFloat
        let verticalOffset: CGFloat
        
        init(
            imageName: String,
            darkImageName: String? = nil,
            message: String,
            buttonTitle: String,
            imageScale: CGFloat,
            verticalOffset: CGFloat
        ) {
            self.imageName = imageName
            self.darkImageName = darkImageName
            self.message = message
            self.buttonTitle = buttonTitle
            self.imageScale = imageScale
            self.verticalOffset = verticalOffset
        }
    }
    
    private let pages: [IntroPage] = [
        IntroPage(
            imageName: "onboarding1-1",
            message: "You can achieve anything through self-motivation.",
            buttonTitle: "Continue",
            imageScale: 0.96,
            verticalOffset: 12
        ),
        IntroPage(
            imageName: "onboarding1-2",
            message: "You don't need strong willpower.",
            buttonTitle: "Continue",
            imageScale: 0.96,
            verticalOffset: 12
        ),
        IntroPage(
            imageName: "onboarding1-3",
            message: "All you need is self motivation 1000 times.",
            buttonTitle: "Let's start",
            imageScale: 0.96,
            verticalOffset: 12
        )
    ]
    
    @State private var currentPage = 0
    let onFinish: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var currentIndex: Int {
        guard !pages.isEmpty else { return 0 }
        return min(max(currentPage, 0), pages.count - 1)
    }

    private let reservedHeaderHeight: CGFloat = 110

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: reservedHeaderHeight)
                    .accessibilityHidden(true)

                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        introPageView(for: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(height: 500)

                Spacer(minLength: 0)
                
                pageIndicator
                    .padding(.bottom, 24)
                
                OnboardingContinueButton(
                    title: pages[currentIndex].buttonTitle,
                    isEnabled: true
                ) {
                    handleContinue()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .fontDesign(.serif)
        .animation(.easeInOut, value: currentIndex)
        .onChange(of: currentPage) { oldValue, newValue in
            guard newValue != oldValue, pages.indices.contains(newValue) else { return }
            HapticManager.shared.trigger(.lightImpact)
        }
    }
    
    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.purple : Color.purple.opacity(0.2))
                    .frame(width: index == currentIndex ? 12 : 8, height: index == currentIndex ? 12 : 8)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
    }

    private func introPageView(for page: IntroPage) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            ZStack(alignment: .bottom) {
                Image(resolvedImageName(for: page))
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(page.imageScale)
                    .frame(maxWidth: 340, maxHeight: 320)
                    .padding(.horizontal, 36)
                    .offset(y: page.verticalOffset)
            }
            .frame(height: 320, alignment: .bottom)
            
            Text(page.message)
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 120, alignment: .top)
                .layoutPriority(1)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleContinue() {
        if currentIndex < pages.count - 1 {
            currentPage += 1
        } else {
            onFinish()
        }
    }

    private func resolvedImageName(for page: IntroPage) -> String {
        if colorScheme == .dark, let darkImageName = page.darkImageName {
            return darkImageName
        }
        return page.imageName
    }
}

#Preview {
    OnboardingIntroView(onFinish: {})
}

