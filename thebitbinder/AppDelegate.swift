import UIKit
import AVFoundation
import UserNotifications
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = MemoryManager.shared
        _ = iCloudKeyValueStore.shared
        
        // Configure audio session app-wide for both playback and recording
        configureAudioSession()
        
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        NotificationManager.shared.scheduleIfNeeded()
        
        // Required for CloudKit silent push notifications between devices
        application.registerForRemoteNotifications()
        
        // Verify iCloud account using the correct container
        Task {
            do {
                let status = try await CKContainer(identifier: "iCloud.666bit").accountStatus()
                switch status {
                case .available:
                    print("✅ [CloudKit] iCloud account available — sync enabled")
                case .noAccount:
                    print("⚠️ [CloudKit] No iCloud account — sync disabled")
                case .restricted:
                    print("⚠️ [CloudKit] iCloud restricted — sync disabled")
                case .couldNotDetermine:
                    print("⚠️ [CloudKit] Could not determine iCloud status")
                case .temporarilyUnavailable:
                    print("⚠️ [CloudKit] iCloud temporarily unavailable")
                @unknown default:
                    print("⚠️ [CloudKit] Unknown iCloud status: \(status.rawValue)")
                }
            } catch {
                print("❌ [CloudKit] Error checking account: \(error)")
            }
        }
        
        return true
    }
    
    // MARK: - Remote Notification Handling (CloudKit Sync)
    
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("✅ [CloudKit] Registered for remote notifications")
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("⚠️ [CloudKit] Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // THIS IS THE KEY METHOD — CloudKit sends a silent push when another device
    // writes data. We must call the completion handler with .newData so iOS knows
    // we processed it, and post the NSPersistentStoreRemoteChange notification
    // so SwiftData merges the incoming records into the local store immediately.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // Let CloudKit process the notification (subscription-based record changes)
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        
        if notification?.notificationType == .recordZone ||
           notification?.notificationType == .query ||
           notification?.notificationType == .database {
            // Trigger SwiftData to merge remote changes
            NotificationCenter.default.post(
                name: .NSPersistentStoreRemoteChange,
                object: nil,
                userInfo: userInfo
            )
            print("🔄 [CloudKit] Remote notification received — merging changes")
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        MemoryManager.shared.handleMemoryWarning()
    }
    
    // MARK: - Audio Session Configuration
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .defaultToSpeaker,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .allowAirPlay,
                    .mixWithOthers
                ]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("✅ [Audio] Audio session configured for playback and recording")
        } catch {
            print("❌ [Audio] Failed to configure audio session: \(error.localizedDescription)")
        }
    }
}
