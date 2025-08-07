## Technical Goals
- Use the latest iOS technical stack

## Project Overview
SelfLie is a habit reinforcement app that helps users build or quit habits through voice-based self-affirmation repetition. Users create personal affirmations, record them in their own voice, then practice by listening and repeating 1000+ times to reinforce belief patterns.

## Technical Requirements

### iOS Version & Frameworks
- **Target**: iOS 16+ minimum (for NavigationStack and latest SwiftUI features)
- **Language**: Swift with SwiftUI
- **Navigation**: NavigationStack (not deprecated NavigationView)
- **State Management**: @Observable macro (iOS 17+) with MVVM architecture
- **Core Frameworks**:
  - AVFoundation: Audio recording and playback
  - Speech: Speech-to-text verification
  - Core Data: Local data persistence
- Minimum support up to iOS 17

### App Architecture
- **Pattern**: MVVM with @Observable ViewModels
- **Navigation**: NavigationStack with .fullScreenCover for practice screen
- **Data Flow**: Local-first with Core Data storage
- **Audio Storage**: Local file system for recorded affirmations

### Core User Flows

#### Creation Flow: Screen 1 → 2 → 3 → 1
1. Dashboard with affirmation list
2. Add affirmation text input
3. Voice recording with speech verification
4. Return to updated dashboard

#### Practice Flow: Screen 1 → 4 (fullScreenCover) → 1
1. Tap play button on existing affirmation
2. Auto-play → record → verify → count → dismiss cycle
3. Counter increments only with successful speech verification
4. "Can't speak now" option for silent environments

### Data Model
```swift
struct Affirmation {
    let id: UUID
    let text: String
    let audioURL: URL
    var repeatCount: Int
    let targetCount: Int = 1000
    let dateCreated: Date
}
```

### MVP Scope
- Basic functionality only
- No gamification, celebrations, or advanced features
- Focus on core voice repetition cycle

## Build Notes
- Reminder to modify code and attempt build for iPhone100

## Development Workflow
- Use 'Explore, plan, code, commit' workflow, you must ask permission before code and commit