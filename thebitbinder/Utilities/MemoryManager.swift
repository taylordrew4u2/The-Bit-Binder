//
//  MemoryManager.swift
//  thebitbinder
//
//  Memory management utility for the app
//

import UIKit
import Foundation

/// Centralized memory management for the app.
///
/// `@MainActor`-isolated so its mutable state (`isClearing`, observer tokens)
/// and the @MainActor services it touches (`BitBuddyService`) are accessed
/// without implicit sync hops from notification-observer callbacks.
@MainActor
final class MemoryManager {
    static let shared = MemoryManager()

    // MARK: - Tunables

    /// Resident size (MB) above which we treat memory as "under pressure"
    /// and trigger preemptive cleanups before expensive operations.
    /// Chosen empirically for ~3x headroom vs. a 600MB jetsam on older devices.
    private static let memoryPressureThresholdMB: Double = 200

    /// Memory capacity URLCache is restored to after a pressure-triggered flush.
    /// Deliberately small — we prefer cold disk fetches over holding memory for images.
    private static let postFlushURLCacheBytes: Int = 2 * 1024 * 1024

    /// Track if we're currently clearing caches to avoid duplicate work
    private var isClearing = false

    /// Observers for cleanup
    private var memoryWarningObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    private init() {
        setupObservers()
    }

    // No deinit: this is a process-lifetime singleton, so the observers
    // live as long as the app. Removing `deinit` avoids the Swift-6 isolation
    // conflict that arises when a `@MainActor` class has a nonisolated deinit
    // that touches instance state.

    private func setupObservers() {
        // Memory warning - highest priority.
        // `queue: .main` guarantees the closure body runs on the main thread,
        // so `MainActor.assumeIsolated` is sound and avoids the async hop
        // (and accompanying `unsafeForcedSync` runtime warning) that an
        // unannotated closure would otherwise trigger when calling into
        // `@MainActor` instance methods.
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMemoryWarning()
            }
        }

        // Background transition - clear caches to reduce footprint
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleBackgroundTransition()
            }
        }

        // Foreground transition - good time to report memory state
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleForegroundTransition()
            }
        }
    }
    
    /// Called when system sends memory warning.
    ///
    /// Returns quickly — iOS expects memory-warning handlers to yield control
    /// back fast, so the actual cleanup is deferred to the next runloop via
    /// a `Task { @MainActor }`. MainActor isolation serialises access to
    /// `isClearing`, so no explicit lock is needed.
    func handleMemoryWarning() {
        guard !isClearing else { return }
        isClearing = true

        print(" [MemoryManager] Memory warning received - clearing caches")
        reportMemoryUsage()

        Task { @MainActor [weak self] in
            // 1. Clear URL caches
            URLCache.shared.removeAllCachedResponses()
            URLCache.shared.memoryCapacity = 0
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s breather
            URLCache.shared.memoryCapacity = MemoryManager.postFlushURLCacheBytes

            // 2. Clear BitBuddy conversation history — can be substantial after
            //    many turns, and is not user-critical data.
            BitBuddyService.shared.startNewConversation()

            // 3. Clear temp files (scratch recordings, import artifacts, etc.)
            self?.clearTempFiles()

            // 4. Notify listeners (SpeechRecognizer, import pipeline, etc.)
            NotificationCenter.default.post(name: .appMemoryWarning, object: nil)

            self?.reportMemoryUsage()
            print(" [MemoryManager] Caches cleared")

            self?.isClearing = false
        }
    }
    
    /// Called when app enters background
    func handleBackgroundTransition() {
        print(" [MemoryManager] App entering background - reducing memory footprint")
        
        // Clear URL caches
        URLCache.shared.removeAllCachedResponses()
        
        // Clear temp files to reduce footprint while backgrounded
        clearTempFiles()
        
        // Release BitBuddy conversation history
        Task { @MainActor in
            BitBuddyService.shared.startNewConversation()
        }
    }
    
    /// Called when app enters foreground
    private func handleForegroundTransition() {
        #if DEBUG
        reportMemoryUsage()
        #endif
    }
    
    /// Call this to proactively reduce memory usage
    func reduceMemoryUsage() {
        handleMemoryWarning()
    }
    
    /// Report current memory usage
    func reportMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            print(" [MemoryManager] Memory usage: \(String(format: "%.1f", usedMB)) MB")
        }
    }
    
    /// Check if memory pressure is high (useful for deciding whether to load large assets)
    func isMemoryPressureHigh() -> Bool {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            return usedMB > MemoryManager.memoryPressureThresholdMB
        }
        return false
    }
    
    /// Call before starting an expensive operation (backup, validation, import).
    /// If memory is already above threshold, triggers a cleanup first.
    func ensureMemoryHeadroom() {
        if isMemoryPressureHigh() {
            print(" [MemoryManager] Memory pressure high before expensive operation — preemptive cleanup")
            reduceMemoryUsage()
        }
    }
    
    /// Removes all files from the app's temporary directory.
    /// Safe to call at any time — only affects throwaway caches/scratch files.
    private func clearTempFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        ) else { return }
        var removed = 0
        for file in files {
            do {
                try FileManager.default.removeItem(at: file)
                removed += 1
            } catch {
                // Temp files in use — skip silently
            }
        }
        if removed > 0 {
            print(" [MemoryManager] Cleared \(removed) temp file(s)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let appMemoryWarning = Notification.Name("appMemoryWarning")
}
