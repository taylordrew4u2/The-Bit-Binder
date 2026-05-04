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
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMemoryWarning()
            }
        }

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleBackgroundTransition()
            }
        }

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
    /// Keep this path distinct from proactive cleanup so logs accurately
    /// reflect whether the OS warned or we voluntarily reduced pressure.
    func handleMemoryWarning() {
        performCleanup(reason: "Memory warning received")
    }

    private func performCleanup(reason: String) {
        guard !isClearing else { return }
        isClearing = true

        print(" [MemoryManager] \(reason) - clearing caches")
        reportMemoryUsage()

        // 1. Clear URL caches immediately.
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.memoryCapacity = 0

        // 2. Clear temp files (scratch recordings, import artifacts, etc.).
        clearTempFiles()

        // 3. Clear BitBuddy conversation history — can be substantial after
        //    many turns, and is not user-critical data.
        BitBuddyService.shared.startNewConversation()

        // 4. Restore a small in-memory cache budget on the next runloop tick.
        DispatchQueue.main.async { [weak self] in
            URLCache.shared.memoryCapacity = MemoryManager.postFlushURLCacheBytes
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
        BitBuddyService.shared.startNewConversation()
    }
    
    /// Called when app enters foreground
    private func handleForegroundTransition() {
        #if DEBUG
        reportMemoryUsage()
        #endif
    }
    
    /// Call this to proactively reduce memory usage
    func reduceMemoryUsage() {
        performCleanup(reason: "Preemptive memory cleanup")
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
