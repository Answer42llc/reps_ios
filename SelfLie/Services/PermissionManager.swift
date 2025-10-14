import AVFoundation
import Speech
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@Observable
class PermissionManager {

    enum PermissionType {
        case microphone
        case speechRecognition
        case notifications
    }
    
    // MARK: - Microphone Permission (iOS 17+)
    static func requestMicrophonePermission() async -> Bool {
        return await AVAudioApplication.requestRecordPermission()
    }
    
    static func microphonePermissionStatus() -> AVAudioApplication.recordPermission {
        // Note: Using AVAudioApplication API (iOS 17+) with legacy return type for compatibility
        // The deprecation warnings will be resolved in future iOS SDK updates
        let permission = AVAudioApplication.shared.recordPermission
        switch permission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .denied
        }
    }
    
    // MARK: - Speech Recognition Permission
    static func requestSpeechRecognitionPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }
    
    static func speechRecognitionPermissionStatus() -> SFSpeechRecognizerAuthorizationStatus {
        return SFSpeechRecognizer.authorizationStatus()
    }
    
    // MARK: - Notification Permission
    static func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            var options: UNAuthorizationOptions = [.alert, .sound, .badge]
            if #available(iOS 15.0, *) {
                options.insert(.timeSensitive)
            }
            let granted = try await center.requestAuthorization(options: options)
            return granted
        } catch {
            return false
        }
    }
    
    static func notificationPermissionStatus() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    @MainActor
    static func openSettings(for permission: PermissionType? = nil) {
        #if canImport(UIKit)
        _ = permission
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
        #endif
    }
}
