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
- Must use this device to build:             { platform:iOS Simulator, arch:arm64, id:2584B20C-69FC-4329-B5F3-C58C31B8B20F, OS:26.0, name:iPad (A16) }

## Development Workflow
- Use 'Explore, plan, code, commit' workflow, you must ask permission before code and commit

## Code Review Guidelines
- During code review, always list specific:
  - Code snippets
  - Relevant files
  - Exact line numbers
  - Provide concrete code suggestions for improvements
  - 在进行review时候，给出最终的review问题清单前，请对清单上的每个问题进行二次验证，确保问题是存在的。

## Analysis and Problem-Solving Guidelines
- Must use ultrathink when analyzing issues
- Find definitive code paths that lead to issues, not potential paths
- When unclear, thoroughly examine code and search documentation to verify
- Always show relevant code when presenting analysis results

## Language Processing Guidelines
- If instructions are not in English, first translate to English before processing
- Conduct entire thinking process in English
- Ensure accurate and context-aware translation
- Always maintain the original intent of the instruction

## Code Editing Guidelines
- When your plan is about to edit codes, you MUST show what currently needs to be fixed and what the new codes after fixed.
- 完成修改后进入 plan mode
- 尽量避免使用任何的time delay来解决问题，请使用更加可靠的解决方案，直击问题本身。
- 你需要对你的每一个想法进行反思，是必要的吗？是解决根本问题的方案吗？是最简单的方案吗？
- 不要炫技，注意问题边界，不要一次解决多个问题。

## Design Philosophy
- 更多使用系统的能力而非自己手动实现，更多让系统默认控制而非自己实现控制，因为iOS默认的情况一般是最符合用户直觉的。
- 计划中应该包含具体要改的代码，以及如何改，修改前后的代码都要列出来
- 'allowBluetooth' was deprecated in iOS 8.0: renamed to 'AVAudioSession.CategoryOptions.allowBluetoothHFP'
- 完成任务后默认进入 plan mode
- use .allowBluetoothHFP instead of .allowBluetooth, 'allowBluetooth' was deprecated in iOS 8.0: renamed to 'AVAudioSession.CategoryOptions.allowBluetoothHFP', Use 'AVAudioSession.CategoryOptions.allowBluetoothHFP' instead