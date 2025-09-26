import SwiftUI
import CoreData

struct PracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("privacyModeEnabled") private var privacyModeEnabled: Bool = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Affirmation.dateCreated, ascending: false)],
        predicate: NSPredicate(format: "isArchived == NO OR isArchived == nil")
    ) private var affirmations: FetchedResults<Affirmation>

    let affirmation: Affirmation

    @State private var currentIndex: Int = 0
    @State private var hasInitializedIndex = false
    @State private var closeTrigger: Int = 0
    @State private var restartTrigger: Int = 0
    @State private var pagerShouldAnimate = false
    @State private var pagerOffset: CGFloat = 0
    @State private var targetIndex: Int? = nil
    @State private var isTransitioning = false
    @State private var lastKnownPageHeight: CGFloat = 0

    private let pageAnimationDuration: Double = 0.28
    private var pageAnimation: Animation { .easeInOut(duration: pageAnimationDuration) }

    private var affirmationIDs: [NSManagedObjectID] {
        affirmations.map { $0.objectID }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                pagerContent(width: geometry.size.width, height: geometry.size.height)
                    .onAppear {
                        lastKnownPageHeight = geometry.size.height
                    }
                    .onChange(of: geometry.size.height) { newHeight in
                        lastKnownPageHeight = newHeight
                    }

                topBar
            }
        }
        .onAppear {
            initializeIndexIfNeeded()
        }
        .onChange(of: affirmationIDs) { _ in
            initializeIndexIfNeeded()
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: {
                HapticManager.shared.trigger(.lightImpact)
                closeTrigger += 1
            }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 20)
            .padding(.top, 20)

            Spacer()

            HStack(spacing: 8) {
                Text("Privacy mode")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Toggle("", isOn: $privacyModeEnabled)
                    .labelsHidden()
            }
            .padding(.trailing, 20)
            .padding(.top, 20)
        }
    }

    private func pagerContent(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(affirmations.indices, id: \.self) { index in
                PracticeSessionView(
                    affirmation: affirmations[index],
                    isActive: index == currentIndex,
                    closeTrigger: closeTrigger,
                    restartTrigger: restartTrigger,
                    onRequestNext: goToNext,
                    onDismiss: handleDismiss
                )
                .frame(width: width, height: height)
                .offset(y: offset(for: index, pageHeight: height) + pagerOffset)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .gesture(dragGesture(pageHeight: height))
    }

    private func offset(for index: Int, pageHeight: CGFloat) -> CGFloat {
        CGFloat(index - currentIndex) * pageHeight
    }

    private func dragGesture(pageHeight: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isTransitioning else { return }
                pagerOffset = value.translation.height
            }
            .onEnded { value in
                guard !isTransitioning else {
                    withAnimation(pageAnimation) { pagerOffset = 0 }
                    return
                }
                guard affirmations.count > 0 else {
                    withAnimation(pageAnimation) { pagerOffset = 0 }
                    return
                }
                handleDragEnd(translation: value.translation.height, pageHeight: pageHeight)
            }
    }

    private func handleDragEnd(translation: CGFloat, pageHeight: CGFloat) {
        lastKnownPageHeight = pageHeight
        let threshold = pageHeight * 0.25
        let direction: Int
        if translation < -threshold {
            direction = 1
        } else if translation > threshold {
            direction = -1
        } else {
            direction = 0
        }

        guard direction != 0 else {
            withAnimation(pageAnimation) {
                pagerOffset = 0
            }
            return
        }

        guard affirmations.count > 1 else {
            withAnimation(pageAnimation) {
                pagerOffset = 0
            }
            return
        }

        beginPageTransition(direction: direction, pageHeight: pageHeight, animated: true)
    }

    private func goToNext() {
        performPageChange(direction: 1)
    }

    private func goToPrevious() {
        performPageChange(direction: -1)
    }

    private func performPageChange(direction: Int, animated: Bool = true) {
        guard !affirmations.isEmpty else { return }
        guard direction != 0 else { return }

        if affirmations.count == 1 {
            restartTrigger += 1
            withAnimation(pageAnimation) {
                pagerOffset = 0
            }
            return
        }

        let height = lastKnownPageHeight > 0 ? lastKnownPageHeight : UIScreen.main.bounds.height
        beginPageTransition(direction: direction, pageHeight: height, animated: animated)
    }

    private func updateIndex(to newIndex: Int) {
        if newIndex == currentIndex {
            restartTrigger += 1
        } else {
            currentIndex = newIndex
            HapticManager.shared.trigger(.lightImpact)
        }
    }

    private func beginPageTransition(direction: Int, pageHeight: CGFloat, animated: Bool) {
        guard !isTransitioning else { return }

        let count = affirmations.count
        guard count > 1 else {
            withAnimation(pageAnimation) {
                pagerOffset = 0
            }
            return
        }

        let computedTarget = (currentIndex + direction + count) % count

        if computedTarget == currentIndex {
            restartTrigger += 1
            withAnimation(pageAnimation) {
                pagerOffset = 0
            }
            return
        }

        targetIndex = computedTarget
        isTransitioning = true

        let shouldAnimate = animated && pagerShouldAnimate && pageHeight > 0

        guard shouldAnimate else {
            withAnimation(.none) {
                updateIndex(to: computedTarget)
                pagerOffset = 0
            }
            resetTransitionState()
            return
        }

        let outgoingOffset = direction == 1 ? -pageHeight : pageHeight

        withAnimation(pageAnimation) {
            pagerOffset = outgoingOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pageAnimationDuration) {
            completeTransitionIfNeeded(expectedIndex: computedTarget)
        }
    }

    private func completeTransitionIfNeeded(expectedIndex: Int) {
        guard isTransitioning, targetIndex == expectedIndex else { return }

        withAnimation(.none) {
            updateIndex(to: expectedIndex)
            pagerOffset = 0
        }

        resetTransitionState()
    }

    private func resetTransitionState() {
        targetIndex = nil
        isTransitioning = false
    }

    private func initializeIndexIfNeeded() {
        guard !hasInitializedIndex else { return }
        if let targetIndex = affirmations.firstIndex(where: { $0.objectID == affirmation.objectID }) {
            currentIndex = targetIndex
        } else if !affirmations.isEmpty {
            currentIndex = 0
        }
        hasInitializedIndex = true
        pagerShouldAnimate = true
    }

    private func handleDismiss() {
        dismiss()
    }
}

struct PracticeSessionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CloudSyncService.self) private var cloudSyncService
    
    let affirmation: Affirmation
    let isActive: Bool
    let closeTrigger: Int
    let restartTrigger: Int
    let onRequestNext: () -> Void
    let onDismiss: () -> Void

    // Privacy Mode (PracticeView only) - default OFF
    @AppStorage("privacyModeEnabled") private var privacyModeEnabled: Bool = false
    @State private var isMutedForPrivacy: Bool = false
    @State private var privacyHighlightTimer: Timer?
    @State private var privacyHighlightStartTime: Date?
    private let privacyMutedHintText: String = "Muted for privacy"
    
    @State private var audioService = AudioService()
    @State private var speechService = SpeechService()
    @State private var practiceState: PracticeState = .initial
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var similarity: Float = 0.0
    @State private var silentRecordingDetected = false
    
    // Word highlighting states
    @State internal var highlightedWordIndices: Set<Int> = []
    @State internal var currentWordIndex: Int = -1
    @State private var wordTimings: [WordTiming] = []
    @State private var audioDuration: TimeInterval = 0
    
    // Replay functionality
    @State private var isReplaying = false
    @State private var replayWaveLevel = 1
    
    // Smart recording stop
    @State private var maxRecordingTimer: Timer?
    @State private var recordingStartTime: Date?
    @State private var hasGoodSimilarity = false
    
    // Performance timing
    @State private var appearTime: Date?
    
    // 优化：预准备状态切换数据
    @State private var isPreparingForRecording = false
    
    // 防重复分析
    @State private var capturedRecognitionText: String = ""
    @State private var hasProcessedFinalAnalysis = false

    // 语言检测缓存
    @State private var cachedLanguageResult: String? = nil
    @State private var hasPerformedLanguageDetection = false

    @State private var sessionCancellationRequested = false
    @State private var isClosing = false
    
    // 临时录音文件URL - 使用@State确保一致性
    @State private var practiceURL: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
    }()
    
    // Helper function to calculate elapsed time with millisecond precision
    private func elapsedTime(from startTime: Date?) -> String {
        guard let startTime = startTime else { return "N/A" }
        let elapsed = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds
        return String(format: "%.0fms", elapsed)
    }
    
    // Helper function to verify file existence with logging
    private func verifyFileExists(at url: URL, context: String = "") -> Bool {
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !exists {
            print("❌ [PracticeView] File not found at: \(url.path) \(context.isEmpty ? "" : "(\(context))")")
        }
        return exists
    }

    private func shouldAbortDueToCancellation(_ context: String) -> Bool {
        if Task.isCancelled {
            print("⏰ [PracticeView] Task cancelled during \(context) - aborting")
            return true
        }
        if sessionCancellationRequested {
            print("⏰ [PracticeView] Session cancellation requested during \(context) - aborting")
            return true
        }
        return false
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return true
        }
        return false
    }

    private func handleActivationChange(_ isActive: Bool) async {
        if isActive {
            await MainActor.run {
                sessionCancellationRequested = false
            }
            await activateSession()
        } else {
            await MainActor.run {
                sessionCancellationRequested = true
            }
            await deactivateSession()
        }
    }

    private func activateSession() async {
        await MainActor.run {
            appearTime = Date()
            isClosing = false
            print("⏰ [PracticeView] View appeared at \(elapsedTime(from: appearTime))")
            resetStateForNewAttempt()
        }
        if shouldAbortDueToCancellation("activation preparation") {
            print("⏰ [PracticeView] Activation cancelled before preparation")
            return
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if shouldAbortDueToCancellation("activation delay") {
            print("⏰ [PracticeView] Activation cancelled during initial delay")
            return
        }
        setupServiceCallbacks()
        performInitialLanguageDetection()
        if shouldAbortDueToCancellation("pre-startPracticeFlow") {
            print("⏰ [PracticeView] Activation cancelled before startPracticeFlow")
            return
        }
        await startPracticeFlow()
    }

    private func deactivateSession() async {
        cleanupForRestart()
        await MainActor.run {
            resetStateForNewAttempt()
        }
    }

    private func handleCloseRequest() async {
        let shouldProceed = await MainActor.run { () -> Bool in
            if isClosing { return false }
            isClosing = true
            sessionCancellationRequested = true
            return true
        }
        guard shouldProceed else { return }
        Task { await cleanup() }
        await MainActor.run {
            onDismiss()
        }
    }

    private func advanceToNextAffirmation() async {
        await MainActor.run {
            sessionCancellationRequested = true
        }
        cleanupForRestart()
        await MainActor.run {
            resetStateForNewAttempt()
            onRequestNext()
        }
    }

    private func performManualRestart() async {
        await MainActor.run {
            sessionCancellationRequested = true
        }
        await deactivateSession()
        await MainActor.run {
            sessionCancellationRequested = false
        }
        await activateSession()
    }

    @MainActor
    private func resetStateForNewAttempt() {
        similarity = 0.0
        silentRecordingDetected = false
        highlightedWordIndices.removeAll()
        currentWordIndex = -1
        wordTimings.removeAll()
        audioDuration = 0
        isReplaying = false
        replayWaveLevel = 1
        recordingStartTime = nil
        hasGoodSimilarity = false
        isPreparingForRecording = false
        capturedRecognitionText = ""
        hasProcessedFinalAnalysis = false
        practiceState = .initial
        speechService.recognizedText = ""
        speechService.recognizedWords.removeAll()
        privacyHighlightTimer?.invalidate()
        privacyHighlightTimer = nil
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        practiceURL = makeNewPracticeURL()
        isClosing = false
        _ = refreshPrivacyMuteState()
    }

    private func makeNewPracticeURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
    }
    
    @MainActor
    private func refreshPrivacyMuteState() -> Bool {
        guard privacyModeEnabled else {
            isMutedForPrivacy = false
            return false
        }
        let shouldMute = !AudioSessionManager.shared.isHeadsetConnected()
        isMutedForPrivacy = shouldMute
        return shouldMute
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color(UIColor.systemGroupedBackground) // Adapts to dark/light mode
                .ignoresSafeArea()
            VStack(spacing: 0) {
                cardView
                    .padding(.top, 88)
                Spacer()
                externalActionArea
                    .padding(.bottom, 40)
            }
        }
        .task(id: isActive) {
            await handleActivationChange(isActive)
        }
        .onChange(of: closeTrigger) { _ in
            guard isActive else { return }
            Task {
                await handleCloseRequest()
            }
        }
        .onChange(of: restartTrigger) { _ in
            guard isActive else { return }
            Task {
                await performManualRestart()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                onDismiss()
            }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: speechService.recognizedText) { _, newText in
            // Monitor for smart recording stop
            if practiceState == .recording && !newText.isEmpty {
                // 捕获识别文本用于后续分析，避免在清理过程中丢失
                capturedRecognitionText = newText
                print("📝 [PracticeView] Captured recognition text: '\(newText)'")
                
                let currentSimilarity = speechService.calculateSimilarity(
                    expected: affirmation.text, 
                    recognized: newText
                )
                
                if currentSimilarity >= 0.8 && !hasGoodSimilarity {
                    hasGoodSimilarity = true
                    print("🎯 Good similarity achieved: \(currentSimilarity)")
                    monitorSilenceForSmartStop()
                }
            }
        }
    }
    
    
    private var affirmationTextView: some View {
        NativeTextHighlighter(
            text: affirmation.text,
            highlightedWordIndices: highlightedWordIndices,
            currentWordIndex: currentWordIndex
        )
        .padding(.horizontal)
    }
    
    
    
    
    private var cardView: some View {
        VStack(spacing: 0) {
            // Card content will go here
            cardContent
        }
        .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var cardContent: some View {
        VStack(spacing: 24) {
            // Status area
            statusArea
            // Content area
            contentArea
            
            // Action area (inside card)
            if practiceState == .completed && (silentRecordingDetected || similarity < 0.8) {
                cardActionArea
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)

    }
    
    private var statusArea: some View {
        VStack(spacing: 8) {
            if practiceState != .completed {
                // Show status during active states
                Text(currentStatusText)
                .fontDesign(.default)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Capsule().fill(.purple))
            } else if !silentRecordingDetected && similarity >= 0.8 {
                // Success state shows checkmark
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
            }else{
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
            // For failure states, no status indicator is shown (matches design)
        }
        .fontDesign(.default)
    }
    
    private var contentArea: some View {
        VStack(spacing: 16) {
            // Main affirmation text
            affirmationTextView
            // Privacy muted hint directly under affirmation when playing muted
            if privacyModeEnabled && isMutedForPrivacy && practiceState == .playing {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.slash.fill")
                        .foregroundColor(.secondary)
                    Text(privacyMutedHintText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            // Replay button (shown after recording ends) with modified visibility
            replayButton
                .opacity(practiceState == .completed ? 1 : 0)
                .allowsHitTesting(practiceState == .completed)
            // Hint text
            hintText
            
        }
    }
    
    private var cardActionArea: some View {
        Button(action: {
            HapticManager.shared.trigger(.lightImpact)
            Task {
                await restartPractice()
            }
        }, label: {
            Image(systemName: "gobackward")
            Text("Restart")
                .fontDesign(.default)
        })
        .padding()
        .background(Color(.secondarySystemBackground))
        .foregroundStyle(.purple)
        .clipShape(Capsule())

    }
    
    private var externalActionArea: some View {
        VStack {
            if practiceState == .completed && !silentRecordingDetected && similarity >= 0.8 {
                Button(action: {
                    HapticManager.shared.trigger(.lightImpact)
                    Task {
                        await advanceToNextAffirmation()
                    }
                }) {
                    Text("Next")
                        .fontDesign(.default)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: 50)
                        .background(Capsule().fill(.purple))
                        .padding(.horizontal, 20)
                }
            }
        }
    }
    
    private var currentStatusText: String {
        switch practiceState {
        case .initial:
            if privacyModeEnabled {
                if privacyModeEnabled {
                    return isMutedForPrivacy ? "Listen in your head" : "Listen..."
                }
            }
            return "Listen..."
        case .playing:
            if privacyModeEnabled {
                return isMutedForPrivacy ? "Listen in your head" : "Listen..."
            }
            return "Listen..."
        case .recording:
            return privacyModeEnabled ? "Say it in your mind" : "Speak now..."
        case .analyzing:
            return "Processing..."
        case .completed:
            return ""
        }
    }
    
    private var hintText: some View {
        Text(practiceState == .playing ? "Your brain believes your own words most." : "Even a lie repeated a thousand times becomes the truth")
            .fontDesign(.default)
            .font(.footnote)
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
    }
    
    private var replayButton: some View {
        Button(action: {
            HapticManager.shared.trigger(.lightImpact)
            Task {
                await replayOriginalAudio()
            }
        }) {
            Image(systemName: speakerIconName)
                .font(.title2)
                .foregroundColor(.purple)
                .frame(width: 44, height: 44)
        }
        .disabled(isReplaying)  // Disable button while playing
    }
    
    // Computed property for dynamic speaker icon
    private var speakerIconName: String {
        if !isReplaying { return "speaker.wave.3.fill" }
        switch replayWaveLevel {
        case 1: return "speaker.wave.1.fill"
        case 2: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
    
    
    private func startPracticeFlow() async {
        if shouldAbortDueToCancellation("startPracticeFlow entry") { return }
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Starting practice flow for affirmation: '\(affirmation.text)'")
        
        // Ensure service callbacks are set up before starting
        await MainActor.run {
            setupServiceCallbacks()
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Service callbacks set up for practice flow")
        }
        if shouldAbortDueToCancellation("startPracticeFlow after setup") { return }
        
        // 重置防重复分析的状态变量
        capturedRecognitionText = ""
        hasProcessedFinalAnalysis = false
        hasGoodSimilarity = false
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Reset analysis state variables")
        if shouldAbortDueToCancellation("startPracticeFlow after reset") { return }
        
        #if targetEnvironment(simulator)
        if privacyModeEnabled {
            // Simulator privacy mode: run highlight-only flow and complete
            await MainActor.run {
                practiceState = .playing
                initializeWordTimings()
                highlightedWordIndices.removeAll()
                currentWordIndex = -1
            }
            await MainActor.run {
                startPrivacySpeakHighlighting()
            }
            return
        } else {
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Running in simulator mode - skipping actual audio/recording")
            await MainActor.run {
                practiceState = .completed
                similarity = 0.8
                incrementCount()
            }
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Simulator flow completed")
        }
        #else
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Running on real device - requesting permissions")
        // Request permissions only when privacy mode is OFF
        if !privacyModeEnabled {
            let permissionStartTime = Date()
            let microphoneGranted = await audioService.requestMicrophonePermission()
            let speechGranted = await speechService.requestSpeechRecognitionPermission()
            let permissionDuration = Date().timeIntervalSince(permissionStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Permissions completed in \(String(format: "%.0fms", permissionDuration)) - Microphone: \(microphoneGranted), Speech: \(speechGranted)")
            guard microphoneGranted && speechGranted else {
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Permission denied - cannot proceed with practice")
                showError("Permissions required for practice session")
                return
            }
        }
        
        // Set up audio session immediately after permissions for playback (first step)
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔧 Setting up audio session for playback")
        let audioSessionStartTime = Date()
        do {
            try await AudioSessionManager.shared.ensureSessionActive()
            let audioSessionDuration = Date().timeIntervalSince(audioSessionStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Audio session ready in \(String(format: "%.0fms", audioSessionDuration))")
        } catch {
            let audioSessionDuration = Date().timeIntervalSince(audioSessionStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Audio session setup failed in \(String(format: "%.0fms", audioSessionDuration)): \(error.localizedDescription)")
            showError("Failed to setup audio session")
            return
        }
        
        if privacyModeEnabled {
            // Privacy: just play (possibly muted); after playback we start privacy highlighting
            if shouldAbortDueToCancellation("privacy playback start") { return }
            await playAffirmation()
        } else {
            // Normal: play + warmup recording in parallel
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🚀 Starting parallel audio playback + recording warmup")
            let parallelStartTime = Date()
            async let audioPlaybackTask: () = playAffirmation()
            async let recordingWarmupTask: () = performRecordingWarmup()
            let _ = await (audioPlaybackTask, recordingWarmupTask)
            let parallelDuration = Date().timeIntervalSince(parallelStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Parallel tasks completed in \(String(format: "%.0fms", parallelDuration))")
        }
        #endif
    }
    
    private func performRecordingWarmup() async {
        if shouldAbortDueToCancellation("recording warmup entry") { return }
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔥 PRECISE: Starting optimized recording warmup")
        let warmupStartTime = Date()
        
        do {
            // 优化：并行执行录音器准备和音频会话预热
            let parallelWarmupStartTime = Date()
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🚀 PRECISE: Starting parallel warmup tasks")
            
            async let recorderPrepTask: Void = {
                let prepStartTime = Date()
                try await audioService.prepareRecording(to: practiceURL)
                let prepDuration = Date().timeIntervalSince(prepStartTime) * 1000
                await MainActor.run {
                    print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Recorder preparation completed in \(String(format: "%.0fms", prepDuration))")
                }
            }()
            
            async let sessionWarmupTask: Void = {
                let warmupTaskStartTime = Date()
                try await AudioSessionManager.shared.preWarmRecording(to: practiceURL)
                let warmupTaskDuration = Date().timeIntervalSince(warmupTaskStartTime) * 1000
                await MainActor.run {
                    print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Audio session warmup completed in \(String(format: "%.0fms", warmupTaskDuration))")
                }
            }()
            
            // 等待并行任务完成
            let _ = try await (recorderPrepTask, sessionWarmupTask)
            
            let parallelDuration = Date().timeIntervalSince(parallelWarmupStartTime) * 1000
            let totalWarmupDuration = Date().timeIntervalSince(warmupStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Parallel warmup tasks completed in \(String(format: "%.0fms", parallelDuration))")
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Total recording warmup completed in \(String(format: "%.0fms", totalWarmupDuration))")
        } catch {
            let warmupDuration = Date().timeIntervalSince(warmupStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ PRECISE: Recording warmup failed in \(String(format: "%.0fms", warmupDuration)): \(error.localizedDescription)")
        }
    }
    
    private func playAffirmation() async {
        if shouldAbortDueToCancellation("playAffirmation entry") { return }
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔊 PRECISE: Starting audio playback stage")
        
        // 优化：直接设置状态，避免MainActor调度延迟
        let stateUpdateStartTime = Date()
        practiceState = .playing
        silentRecordingDetected = false
        // Reset highlighting for fresh playback
        highlightedWordIndices.removeAll()
        currentWordIndex = -1
        // Initialize word timings once at the start of playback
        initializeWordTimings()
        let stateUpdateDuration = Date().timeIntervalSince(stateUpdateStartTime) * 1000
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚡ PRECISE: State update completed in \(String(format: "%.0fms", stateUpdateDuration))")
        
        if shouldAbortDueToCancellation("before resolving audioURL") { return }

        guard let audioURL = affirmation.audioURL else {
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Audio URL not found for affirmation")
            showError("Audio file not found")
            return
        }
        
        // Check if file actually exists
        guard verifyFileExists(at: audioURL, context: "playback verification") else {
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Audio file missing for playback")
            showError("Audio file missing at: \(audioURL.path)")
            return
        }
        
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎵 Playing audio from: \(audioURL.path)")
        
        let playbackStartTime = Date()
        do {
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 📞 About to call audioService.playAudio()")
            let shouldMuteForPrivacy = await MainActor.run { refreshPrivacyMuteState() }
            let desiredVolume: Float = shouldMuteForPrivacy ? 0.0 : 1.0
            if shouldAbortDueToCancellation("before playAudio call") { return }
            try await audioService.playAudio(from: audioURL, volume: desiredVolume)
            let playbackDuration = Date().timeIntervalSince(playbackStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 📞 audioService.playAudio() returned after \(String(format: "%.0fms", playbackDuration))")
            
            if privacyModeEnabled {
                await MainActor.run {
                    startPrivacySpeakHighlighting()
                }
            } else {
                // 精确时间戳：准备调用startOptimizedRecording
                let preRecordingCallTime = Date()
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: About to call startOptimizedRecording at [\(elapsedTime(from: appearTime))]")
                await startOptimizedRecording()
                let recordingCallDuration = Date().timeIntervalSince(preRecordingCallTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: startOptimizedRecording call completed in \(String(format: "%.0fms", recordingCallDuration))")
            }
            
        } catch {
            let playbackDuration = Date().timeIntervalSince(playbackStartTime) * 1000
            if isCancellationError(error) || Task.isCancelled {
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ Audio playback cancelled after \(String(format: "%.0fms", playbackDuration)) - ignoring")
                return
            } else {
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Audio playback failed in \(String(format: "%.0fms", playbackDuration)): \(error.localizedDescription)")
                await MainActor.run {
                    showError("Failed to play audio: \(error.localizedDescription)")
                }
            }
        }
    }

    private func startOptimizedRecording() async {
        if shouldAbortDueToCancellation("startOptimizedRecording entry") { return }
        let methodEntryTime = Date()
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🚀 PRECISE: ENTERED startOptimizedRecording() at [\(elapsedTime(from: appearTime))]")
        
        // 精确测量MainActor调度延迟
        let preMainActorTime = Date()
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: About to call MainActor.run")
        
        await MainActor.run {
            let mainActorEntryTime = Date()
            let mainActorDelay = mainActorEntryTime.timeIntervalSince(preMainActorTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚡ PRECISE: MainActor.run entered after \(String(format: "%.0fms", mainActorDelay)) delay")
            
            // 触发前先准备中等强度触觉
            HapticManager.shared.prepareImpact(.medium)
            practiceState = .recording
            // 状态改变时触发中等强度触觉
            HapticManager.shared.trigger(.mediumImpact)
            print("🎯 [PracticeView] Triggered MEDIUM haptic feedback at state change to recording - user can speak NOW")
            
            recordingStartTime = Date()
            hasGoodSimilarity = false
            
            // Issue 2 Fix: Reset text highlighting when starting recording
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
            print("🎯 [PracticeView] Reset text highlighting for recording phase")
            
            let mainActorExitTime = Date()
            let mainActorDuration = mainActorExitTime.timeIntervalSince(mainActorEntryTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚡ PRECISE: MainActor.run completed in \(String(format: "%.0fms", mainActorDuration))")
        }
        
        let postMainActorTime = Date()
        let totalMainActorOverhead = postMainActorTime.timeIntervalSince(preMainActorTime) * 1000
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: Total MainActor overhead: \(String(format: "%.0fms", totalMainActorOverhead))")
        
        let recordingSetupStartTime = Date()
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: Recording setup phase started")
        
        do {
            // Since recording is pre-warmed, this should be much faster
            let recorderStartTime = Date()
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🏃‍♂️ PRECISE: About to call audioService.startPreparedRecording()")
            
            try await audioService.startPreparedRecording()
            
            let recorderDuration = Date().timeIntervalSince(recorderStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Pre-warmed recorder started in \(String(format: "%.0fms", recorderDuration))")
            
            // Start real-time speech recognition with retry mechanism
            let speechStartTime = Date()
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🗣️ PRECISE: About to start speech recognition for text: '\(affirmation.text)'")
            
            do {
                try speechService.startRecognition(expectedText: affirmation.text, localeIdentifier: cachedLanguageResult)
                let speechDuration = Date().timeIntervalSince(speechStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Speech recognition started in \(String(format: "%.0fms", speechDuration))")
            } catch {
                let speechDuration = Date().timeIntervalSince(speechStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ PRECISE: Speech recognition failed in \(String(format: "%.0fms", speechDuration)), attempting retry with audio session reset...")
                
                // Try ensuring audio session is active for Code 1101 recovery (without deactivation)
                do {
                    try await AudioSessionManager.shared.ensureSessionActive()
                    let retryStartTime = Date()
                    try speechService.startRecognition(expectedText: affirmation.text, localeIdentifier: cachedLanguageResult)
                    let retryDuration = Date().timeIntervalSince(retryStartTime) * 1000
                    print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Speech recognition retry succeeded in \(String(format: "%.0fms", retryDuration))")
                } catch {
                    let retryTotalDuration = Date().timeIntervalSince(speechStartTime) * 1000
                    print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ PRECISE: Speech recognition retry failed after \(String(format: "%.0fms", retryTotalDuration)): \(error.localizedDescription)")
                    throw error
                }
            }
            
            let setupDuration = Date().timeIntervalSince(recordingSetupStartTime) * 1000
            let totalMethodDuration = Date().timeIntervalSince(methodEntryTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: Recording setup completed in \(String(format: "%.0fms", setupDuration))")
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: Total startOptimizedRecording() duration: \(String(format: "%.0fms", totalMethodDuration))")
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: Method overhead (total - setup): \(String(format: "%.0fms", totalMethodDuration - setupDuration))")
            
            // 优化：直接设置定时器，避免MainActor延迟
            maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                print("⏰ [PracticeView] [\(self.elapsedTime(from: self.appearTime))] ⏰ Maximum recording time reached - stopping recording")
                Task {
                    await self.stopRecording()
                }
            }
            
        } catch {
            let setupDuration = Date().timeIntervalSince(recordingSetupStartTime) * 1000
            let totalMethodDuration = Date().timeIntervalSince(methodEntryTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ PRECISE: Failed to start optimized recording in \(String(format: "%.0fms", setupDuration)): \(error.localizedDescription)")
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ PRECISE: Total failed method duration: \(String(format: "%.0fms", totalMethodDuration))")
            // 优化：直接调用showError，避免MainActor延迟
            showError("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func startRecording() async {
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎤 ENTERED startRecording() method")
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎤 Starting recording stage")
        await MainActor.run {
            // 触发前先准备重击触觉
            HapticManager.shared.prepareImpact(.medium)
            practiceState = .recording
            // Trigger haptic feedback immediately when state changes to recording
            HapticManager.shared.trigger(.mediumImpact)
            print("🎯 [PracticeView] Triggered MEDIUM haptic feedback at state change to recording (backup path) - user can speak NOW")
            
            recordingStartTime = Date()
            hasGoodSimilarity = false
            
            // Issue 2 Fix: Reset text highlighting when starting recording
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
            print("🎯 [PracticeView] Reset text highlighting for recording phase")
        }
        
        let recordingSetupStartTime = Date()
        do {
            // Try to use pre-prepared recorder first, fallback to regular recording
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🚀 Using pre-prepared recorder (prepared at app start)")
            let recorderStartTime = Date()
            do {
                try await audioService.startPreparedRecording()
                
                let recorderDuration = Date().timeIntervalSince(recorderStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Pre-prepared recorder started instantly in \(String(format: "%.0fms", recorderDuration))!")
            } catch {
                let recorderDuration = Date().timeIntervalSince(recorderStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ Pre-prepared recorder unavailable in \(String(format: "%.0fms", recorderDuration)), falling back to regular recording")
                let fallbackStartTime = Date()
                try await audioService.startRecording(to: practiceURL)
                
                let fallbackDuration = Date().timeIntervalSince(fallbackStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Regular recording started successfully in \(String(format: "%.0fms", fallbackDuration))")
            }
            
            // Start real-time speech recognition with retry mechanism
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🗣️ Starting speech recognition for text: '\(affirmation.text)'")
            let speechStartTime = Date()
            do {
                try speechService.startRecognition(expectedText: affirmation.text, localeIdentifier: cachedLanguageResult)
                let speechDuration = Date().timeIntervalSince(speechStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Speech recognition started in \(String(format: "%.0fms", speechDuration))")
            } catch {
                let speechDuration = Date().timeIntervalSince(speechStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ Speech recognition failed in \(String(format: "%.0fms", speechDuration)), attempting retry...")
                // Brief delay before retry
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                let retryStartTime = Date()
                try speechService.startRecognition(expectedText: affirmation.text, localeIdentifier: cachedLanguageResult)
                let retryDuration = Date().timeIntervalSince(retryStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Speech recognition retry succeeded in \(String(format: "%.0fms", retryDuration))")
            }
            
            let setupDuration = Date().timeIntervalSince(recordingSetupStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 Recording setup completed in \(String(format: "%.0fms", setupDuration))")
            
            // Set up maximum recording timer (10 seconds)
            await MainActor.run {
                maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                    print("⏰ [PracticeView] [\(self.elapsedTime(from: self.appearTime))] ⏰ Maximum recording time reached - stopping recording")
                    Task {
                        await self.stopRecording()
                    }
                }
            }
            
        } catch {
            let setupDuration = Date().timeIntervalSince(recordingSetupStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Failed to start recording in \(String(format: "%.0fms", setupDuration)): \(error.localizedDescription)")
            await MainActor.run {
                showError("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }
    
    private func stopRecording() async {
        guard practiceState == .recording else { return }
        
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🛑 Stopping recording")
        await MainActor.run {
            practiceState = .analyzing
        }
        
        // Clean up smart recording timer
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
        // Stop both audio recording and speech recognition
        let stopStartTime = Date()
        audioService.stopRecording()
        speechService.stopRecognition()
        let stopDuration = Date().timeIntervalSince(stopStartTime) * 1000
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Recording services stopped in \(String(format: "%.0fms", stopDuration))")
        
        // Note: With direct highlighting, all recognized characters are already highlighted
        // No need for additional final highlighting step
        
        await analyzeRecording()
    }
    
    private func analyzeRecording() async {
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔍 Starting speech analysis stage")
        
        // 防重复分析：如果已经处理过最终分析，直接返回
        if hasProcessedFinalAnalysis {
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ Final analysis already processed, skipping duplicate")
            return
        }
        
        await MainActor.run {
            practiceState = .analyzing
        }
        
        let analysisStartTime = Date()
        
        // 优先使用最终识别结果
        let finalRecognizedText = speechService.recognizedText.isEmpty ? capturedRecognitionText : speechService.recognizedText
        let recognizedText = finalRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 📝 Using final recognition text: '\(recognizedText)'")
        
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 Expected text: '\(affirmation.text)'")
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Recognized text: '\(recognizedText)'")
        
        // 标记已开始最终分析（在实际处理前设置，确保不会重复）
        hasProcessedFinalAnalysis = true
        
        if recognizedText.isEmpty {
            let analysisDuration = Date().timeIntervalSince(analysisStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔇 No speech detected during recording (analyzed in \(String(format: "%.0fms", analysisDuration)))")
            await MainActor.run {
                silentRecordingDetected = true
                practiceState = .completed
            }
            return
        }
        
        // Calculate similarity using embedding-based comparison
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 📊 Calculating similarity between expected and recognized text")
        let similarityStartTime = Date()
        similarity = speechService.calculateSimilarity(expected: affirmation.text, recognized: recognizedText)
        let similarityDuration = Date().timeIntervalSince(similarityStartTime) * 1000
        
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔍 Calculated similarity: \(similarity) (threshold: 0.8) in \(String(format: "%.0fms", similarityDuration))")
        
        await MainActor.run {
            practiceState = .completed
            
            if similarity >= 0.8 {
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎉 Similarity above threshold - incrementing count")
                HapticManager.shared.trigger(.success)
                incrementCount()
            } else {
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 📈 Similarity below threshold - encouraging retry")
                HapticManager.shared.trigger(.warning)
            }
        }
        
        let totalAnalysisDuration = Date().timeIntervalSince(analysisStartTime) * 1000
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Speech analysis completed in \(String(format: "%.0fms", totalAnalysisDuration))")
    }
    
    @MainActor
    private func incrementCount() {
        affirmation.repeatCount += 1
        affirmation.updatedAt = Date()
        affirmation.lastPracticedAt = Date()

        do {
            try viewContext.save()
            cloudSyncService.enqueueUpload(for: affirmation.objectID)
            NotificationManager.shared.markPracticeCompleted()
        } catch {
            showError("Failed to update progress: \(error.localizedDescription)")
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    private func restartPractice() async {
        print("🔄 [PracticeView] Restarting practice session")
        // Use restart-specific cleanup that doesn't deactivate audio session
        cleanupForRestart()
        
        // Safe audio session reconfiguration without deactivation
        do {
            try await AudioSessionManager.shared.reconfigureSessionSafely()
            print("✅ [PracticeView] Audio session safely reconfigured for restart")
        } catch {
            print("⚠️ [PracticeView] Failed to safely reconfigure audio session: \(error.localizedDescription)")
        }
        
        await MainActor.run {
            resetStateForNewAttempt()
        }
        await startPracticeFlow()
    }
    
    private func resetTextHighlighting() {
        // Reset all text colors to original state unless it's a successful completion
        if silentRecordingDetected || similarity < 0.8 {
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
        }
    }
    
    /// Cleanup for restart - does NOT deactivate audio session to prevent other apps from resuming
    private func cleanupForRestart() {
        print("🧹 [PracticeView] Cleaning up for restart (keeping audio session active)")
        audioService.stopRecording()
        audioService.stopPlayback()
        audioService.cleanupPreparedRecording()
        speechService.stopRecognition()
        privacyHighlightTimer?.invalidate()
        privacyHighlightTimer = nil
        isMutedForPrivacy = false
        
        // Clean up timers
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
        // Clean up temporary recording file
        if verifyFileExists(at: practiceURL, context: "restart cleanup verification") {
            do {
                try FileManager.default.removeItem(at: practiceURL)
                print("🗑️ [PracticeView] Cleaned up temporary recording file for restart: \(practiceURL.path)")
            } catch {
                print("⚠️ [PracticeView] Failed to clean up temp file for restart: \(error.localizedDescription)")
            }
        }
        
        // Clear all callbacks to prevent memory leaks
        print("🧹 [PracticeView] Clearing service callbacks for restart")
        audioService.onPlaybackProgress = nil
        audioService.onPlaybackComplete = nil
        speechService.onWordRecognized = nil
        speechService.onAudioLevelUpdate = nil
        speechService.onSilenceDetected = nil
        
        // Note: Audio session remains active - no deactivation during restart
        print("✅ [PracticeView] Restart cleanup complete - audio session kept active")
    }
    
    /// Full cleanup including audio session deactivation - only for view dismissal
    private func cleanup() async {
        print("🧹 [PracticeView] Full cleanup including audio session deactivation")
        audioService.stopRecording()
        audioService.stopPlayback()
        audioService.cleanupPreparedRecording()
        speechService.stopRecognition()
        privacyHighlightTimer?.invalidate()
        privacyHighlightTimer = nil
        isMutedForPrivacy = false
        
        // Clean up timers
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
        // Clean up temporary recording file
        if verifyFileExists(at: practiceURL, context: "cleanup verification") {
            do {
                try FileManager.default.removeItem(at: practiceURL)
                print("🗑️ [PracticeView] Cleaned up temporary recording file: \(practiceURL.path)")
            } catch {
                print("⚠️ [PracticeView] Failed to clean up temp file: \(error.localizedDescription)")
            }
        }
        
        // Deactivate audio session and notify other apps to resume (Apple Music, etc.)
        print("🎵 [PracticeView] Deactivating audio session to restore other apps' audio")
        do {
            try await AudioSessionManager.shared.deactivateSession()
            print("✅ [PracticeView] Audio session deactivated, other apps can resume playback")
        } catch {
            print("⚠️ [PracticeView] Failed to deactivate audio session: \(error.localizedDescription)")
        }
        
        // Clear all callbacks to prevent memory leaks
        print("🧹 [PracticeView] Clearing service callbacks")
        audioService.onPlaybackProgress = nil
        audioService.onPlaybackComplete = nil
        speechService.onWordRecognized = nil
        speechService.onAudioLevelUpdate = nil
        speechService.onSilenceDetected = nil
    }
    
    private func monitorSilenceForSmartStop() {
        // Set up silence detection callback for smart stop
        speechService.onSilenceDetected = { isSilent in
            if isSilent && self.hasGoodSimilarity && self.practiceState == .recording {
                print("🤫 Silence detected with good similarity - stopping recording")
                Task {
                    await self.stopRecording()
                }
            }
        }
    }
    
    private func performInitialLanguageDetection() {
        if !hasPerformedLanguageDetection {
            let localeIdentifier = LanguageDetector.getLocaleIdentifier(from: affirmation.text)
            cachedLanguageResult = localeIdentifier
            hasPerformedLanguageDetection = true
            print("🌍 [PracticeView] Cached language detection result: \(localeIdentifier)")
        }
    }
    
    private func setupServiceCallbacks() {
        // Audio service playback progress callback
        audioService.onPlaybackProgress = { currentTime, duration in
            
            DispatchQueue.main.async {
                self.audioDuration = duration
                
                // Apply time offset compensation for system delays
                let timeOffset: TimeInterval = 0.05 // 50ms compensation
                let adjustedTime = currentTime + timeOffset
                
                // Note: Audio playback progress logging removed to reduce console noise
                
                // Drive replay icon wave level by playback progress
                if self.isReplaying && duration > 0 {
                    let progress = max(0, min(1, adjustedTime / duration))
                    if progress < 1.0/3.0 {
                        self.replayWaveLevel = 1
                    } else if progress < 2.0/3.0 {
                        self.replayWaveLevel = 2
                    } else {
                        self.replayWaveLevel = 3
                    }
                }
                
                // Update current word index based on playback progress
                let newWordIndex = NativeTextHighlighter.getWordIndexForTime(adjustedTime, wordTimings: self.wordTimings)
                
                if newWordIndex != self.currentWordIndex {
                    self.currentWordIndex = newWordIndex
                    
                    // Optimized highlighting: only highlight completed words
                    self.updateHighlightingWithProgress(currentIndex: newWordIndex, currentTime: adjustedTime)
                }
            }
        }
        
        // Speech service word recognition callback - Direct highlighting for reliability
        speechService.onWordRecognized = { recognizedText, recognizedWordIndices in
            
            DispatchQueue.main.async {
                // Direct highlighting: highlight all recognized characters immediately
                self.highlightedWordIndices.formUnion(recognizedWordIndices)
                
                // Set current word index to the highest recognized word
                if let maxIndex = recognizedWordIndices.max() {
                    self.currentWordIndex = maxIndex
                }
            }
        }
        
        // Audio service playback complete callback
        audioService.onPlaybackComplete = {
            DispatchQueue.main.async {
                // Ensure all words are highlighted when playback completes
                if !self.wordTimings.isEmpty {
                    self.highlightedWordIndices = Set(0..<self.wordTimings.count)
                    self.currentWordIndex = self.wordTimings.count - 1
                }
                // End icon with full waves
                self.replayWaveLevel = 3
                // In privacy mode, after listen stage, move to mental speak highlighting
                if self.privacyModeEnabled {
                    self.startPrivacySpeakHighlighting()
                }
            }
        }
    }
    
    /// Simplified highlighting update - highlight all words up to current index
    private func updateHighlightingWithProgress(currentIndex: Int, currentTime: TimeInterval) {
        if currentIndex >= 0 {
            // Highlight all words from 0 to currentIndex (inclusive)
            self.highlightedWordIndices = Set(0...currentIndex)
        } else {
            self.highlightedWordIndices.removeAll()
        }
    }
    
    private func replayOriginalAudio() async {
        print("🔄 [PracticeView] Replaying original audio")
        guard let audioURL = affirmation.audioURL else {
            showError("Audio file not found")
            return
        }
        
        // Reset highlighting state and ensure callbacks are set up
        await MainActor.run {
            isReplaying = true
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
            // Ensure service callbacks are properly set up for replay
            setupServiceCallbacks()
        }
        
        do {
            try await audioService.playAudio(from: audioURL)
        } catch {
            await MainActor.run {
                showError("Failed to replay audio: \(error.localizedDescription)")
            }
        }
        
        await MainActor.run {
            isReplaying = false
            // Keep highlighting state after replay so user can see final state
            // Don't reset highlighting after replay - let user see the complete highlighted text
        }
    }
    
    /// Initialize word timings using precise data from the affirmation
    private func initializeWordTimings() {
        // Load precise word timings from the affirmation
        wordTimings = affirmation.wordTimings
        
        // 添加详细的时序数据日志
        print("🎯 [PracticeView] Loaded word timings for text: '\(affirmation.text)'")
        print("🎯 [PracticeView] Found \(wordTimings.count) word timings:")
        for (index, timing) in wordTimings.enumerated() {
            print("🎯   [\(index)] '\(timing.word)' -> \(String(format: "%.3f", timing.startTime))s - \(String(format: "%.3f", timing.endTime))s (duration: \(String(format: "%.3f", timing.duration))s, confidence: \(String(format: "%.2f", timing.confidence)))")
        }
        
        // Check if we need to regenerate timings for Chinese text
        let needsRegeneration = shouldRegenerateTimings()
        
        if needsRegeneration {
            print("🔄 [PracticeView] Chinese text detected with incorrect timings, regenerating...")
            Task {
                await regenerateWordTimings()
            }
            return
        }
        
        // If no timings exist, create basic fallback
        if wordTimings.isEmpty {
            print("⚠️ [PracticeView] No word timings available, using fallback")
            createFallbackTimings()
        }
    }
    
    private func shouldRegenerateTimings() -> Bool {
        // Check if it's CJK text with only 1 timing (indicates old word-style processing)
        let isCJK = UniversalTextProcessor.containsCJKCharacters(affirmation.text)
        let hasOnlyOneWord = wordTimings.count == 1
        let textUnits = UniversalTextProcessor.smartSegmentText(affirmation.text)
        let expectedUnitCount = textUnits.count
        
        if isCJK && hasOnlyOneWord && expectedUnitCount > 1 {
            print("🀄 [PracticeView] CJK text '\(affirmation.text)' has only 1 timing but should have \(expectedUnitCount) units")
            return true
        }
        
        return false
    }
    
    private func regenerateWordTimings() async {
        guard let audioURL = affirmation.audioURL,
              verifyFileExists(at: audioURL, context: "word timing regeneration") else {
            print("❌ [PracticeView] Cannot regenerate: audio file not found")
            return
        }
        
        do {
            print("🎯 [PracticeView] Starting background regeneration of word timings")
            let speechService = SpeechService()
            let newWordTimings = try await speechService.analyzeAudioFile(at: audioURL, expectedText: affirmation.text)
            
            await MainActor.run {
                // Update both memory and persistent storage
                self.wordTimings = newWordTimings
                self.affirmation.wordTimings = newWordTimings
                
                // Save to Core Data
                do {
                    try PersistenceController.shared.container.viewContext.save()
                    print("✅ [PracticeView] Regenerated and saved \(newWordTimings.count) word timings")
                    
                    // Log new timing details
                    for (index, timing) in newWordTimings.enumerated() {
                        print("📍 New Word \(index): '\(timing.word)' at \(String(format: "%.2f", timing.startTime))s-\(String(format: "%.2f", timing.endTime))s")
                    }
                } catch {
                    print("❌ [PracticeView] Failed to save regenerated timings: \(error)")
                }
            }
        } catch {
            print("❌ [PracticeView] Failed to regenerate word timings: \(error)")
            await MainActor.run {
                createFallbackTimings()
            }
        }
    }
    
    private func createFallbackTimings() {
        // Create simple fallback timings based on text length using universal processor
        let textUnits = UniversalTextProcessor.smartSegmentText(affirmation.text)
        let words = UniversalTextProcessor.extractTexts(from: textUnits)
        let timePerWord: TimeInterval = audioDuration > 0 ? audioDuration / Double(words.count) : 0.5
        
        wordTimings = words.enumerated().map { index, word in
            WordTiming(
                word: word,
                startTime: Double(index) * timePerWord,
                duration: timePerWord,
                confidence: 0.5
            )
        }
        
        print("📊 [PracticeView] Created \(wordTimings.count) fallback timings using universal processor")
    }

    // MARK: - Privacy Mode Helpers
    private func startPrivacySpeakHighlighting() {
        // Ensure runs on main thread for UI updates
        privacyHighlightTimer?.invalidate()
        privacyHighlightTimer = nil
        privacyHighlightStartTime = Date()
        practiceState = .recording
        highlightedWordIndices.removeAll()
        currentWordIndex = -1
        
        if wordTimings.isEmpty { initializeWordTimings() }
        let totalDuration = wordTimings.last?.endTime ?? max(audioDuration, 0)
        
        privacyHighlightTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(self.privacyHighlightStartTime ?? Date())
            let newIndex = NativeTextHighlighter.getWordIndexForTime(elapsed, wordTimings: self.wordTimings)
            if newIndex != self.currentWordIndex {
                self.currentWordIndex = newIndex
                if newIndex >= 0 { self.highlightedWordIndices = Set(0...newIndex) } else { self.highlightedWordIndices.removeAll() }
            }
            if elapsed >= totalDuration + 0.1 {
                self.privacyHighlightTimer?.invalidate()
                self.privacyHighlightTimer = nil
                // Complete successfully in privacy mode
                self.practiceState = .completed
                self.silentRecordingDetected = false
                self.similarity = 0.8
                HapticManager.shared.trigger(.success)
                self.incrementCount()
            }
        }
        RunLoop.main.add(privacyHighlightTimer!, forMode: .common)
    }
}

// MARK: - Testing Extensions
#if DEBUG
extension PracticeSessionView {
    func simulateRecordingStart() {
        // Reset highlighting state for testing
        highlightedWordIndices.removeAll()
        currentWordIndex = -1
    }
}
#endif

enum PracticeState {
    case initial
    case playing
    case recording
    case analyzing
    case completed
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let sampleAffirmation = Affirmation(context: context)
    sampleAffirmation.id = UUID()
    sampleAffirmation.text = "I never compare to others, because that make no sense"
    sampleAffirmation.audioFileName = "sample.m4a"
    sampleAffirmation.repeatCount = 84
    sampleAffirmation.targetCount = 1000
    sampleAffirmation.dateCreated = Date()
    
    return PracticeView(affirmation: sampleAffirmation)
        .environment(\.managedObjectContext, context)
}
