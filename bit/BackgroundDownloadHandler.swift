//
//  BackgroundDownloadHandler.swift
//  bit
//
//  Created by Taylor Drew on 3/21/26.
//
//  Background Asset Downloader Extension for BitBinder.
//  Uses BADownloaderExtension to schedule and handle background URL downloads
//  (content updates, model files, etc.) with logging and shared app group storage.
//

import BackgroundAssets
import os.log
import ExtensionFoundation

private let logger = Logger(subsystem: "The-BitBinder.thebitbinder.bit", category: "BackgroundDownload")

/// Shared constants between the main app and the background downloader extension.
enum BackgroundDownloadConstants {
    /// App group identifier shared between the main app and this extension.
    static let appGroupIdentifier = "group.The-BitBinder.thebitbinder"
    
    /// The bundle identifier of the main app.
    static let appBundleIdentifier = "The-BitBinder.thebitbinder"
    
    /// UserDefaults key for total downloaded asset count.
    static let downloadedAssetCountKey = "backgroundDownloadedAssetCount"
    
    /// UserDefaults key for download error log.
    static let lastDownloadErrorKey = "lastBackgroundDownloadError"
    
    /// UserDefaults key for pending download identifiers.
    static let pendingDownloadsKey = "pendingBackgroundDownloads"
    
    /// Directory name for downloaded assets within the shared container.
    static let downloadedAssetsDirectory = "BackgroundAssets"
    
    /// The main app's bundle identifier.
    static let appBundleIdentifier = "666bit"
}

@main
struct DownloaderExtension: BADownloaderExtension {
    
    /// Shared UserDefaults for communicating state with the main app.
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: BackgroundDownloadConstants.appGroupIdentifier)
    }
    
    /// Shared container URL for storing downloaded assets.
    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BackgroundDownloadConstants.appGroupIdentifier
        )
    }
    
    // MARK: - BADownloaderExtension — Lifecycle
    
    /// Called when the extension launches. Return any downloads that should be enqueued.
    /// The system calls this on first install, app update, and periodically.
    func extensionWillTerminate() {
        logger.info("🔌 [BackgroundDownload] Extension will terminate")
    }
    
    // MARK: - BADownloaderExtension — Download Events
    
    /// Called when a background download completes successfully.
    func download(_ download: BADownload,
                  didWriteTo path: URL,
                  fileSize: Int) {
        logger.info("✅ [BackgroundDownload] Completed: \(download.identifier, privacy: .public) — \(fileSize) bytes")
        
        // Move the downloaded file into the shared app group container
        ensureSharedAssetsDirectory()
        
        if let destinationDir = sharedContainerURL?.appendingPathComponent(
            BackgroundDownloadConstants.downloadedAssetsDirectory, isDirectory: true
        ) {
            let filename = download.identifier.replacingOccurrences(of: "/", with: "_")
            let destinationURL = destinationDir.appendingPathComponent(filename)
            
            do {
                // Remove existing file if present (e.g. updating a previous version)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: path, to: destinationURL)
                logger.info("📁 [BackgroundDownload] Saved to: \(destinationURL.lastPathComponent, privacy: .public)")
            } catch {
                logger.error("❌ [BackgroundDownload] Failed to move file: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        // Record success in shared UserDefaults
        let defaults = sharedDefaults
        defaults?.set(Date().timeIntervalSince1970, forKey: BackgroundDownloadConstants.lastDownloadTimestampKey)
        
        let previousCount = defaults?.integer(forKey: BackgroundDownloadConstants.downloadedAssetCountKey) ?? 0
        defaults?.set(previousCount + 1, forKey: BackgroundDownloadConstants.downloadedAssetCountKey)
        
        // Clear any previous error
        defaults?.removeObject(forKey: BackgroundDownloadConstants.lastDownloadErrorKey)
        
        // Remove from pending list
        removePendingDownload(download.identifier)
        
        logger.info("📊 [BackgroundDownload] Total assets downloaded: \(previousCount + 1)")
    }
    
    /// Called when a download fails.
    func download(_ download: BADownload, failedWithError error: Error) {
        logger.error("❌ [BackgroundDownload] Failed: \(download.identifier, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        
        // Record the error in shared UserDefaults so the main app can surface it
        let defaults = sharedDefaults
        let errorInfo = "[\(Date())] \(download.identifier): \(error.localizedDescription)"
        defaults?.set(errorInfo, forKey: BackgroundDownloadConstants.lastDownloadErrorKey)
        
        // Remove from pending list
        removePendingDownload(download.identifier)
    }
    
    /// Called when the download receives a challenge. Return `.allow` for trusted sources.
    func download(_ download: BADownload,
                  didReceive challenge: URLAuthenticationChallenge) async
    -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        // Trust the default server certificate validation
        return (.performDefaultHandling, nil)
    }
    
    // MARK: - Helpers
    
    /// Creates the shared assets directory if it doesn't already exist.
    private func ensureSharedAssetsDirectory() {
        guard let containerURL = sharedContainerURL else {
            logger.warning("⚠️ [BackgroundDownload] Could not access shared container")
            return
        }
        
        let assetsDir = containerURL.appendingPathComponent(
            BackgroundDownloadConstants.downloadedAssetsDirectory,
            isDirectory: true
        )
        
        if !FileManager.default.fileExists(atPath: assetsDir.path) {
            do {
                try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
                logger.info("📁 [BackgroundDownload] Created shared assets directory")
            } catch {
                logger.error("❌ [BackgroundDownload] Failed to create assets directory: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    /// Removes a download identifier from the pending list in shared UserDefaults.
    private func removePendingDownload(_ identifier: String) {
        guard let defaults = sharedDefaults else { return }
        var pending = defaults.stringArray(forKey: BackgroundDownloadConstants.pendingDownloadsKey) ?? []
        pending.removeAll { $0 == identifier }
        defaults.set(pending, forKey: BackgroundDownloadConstants.pendingDownloadsKey)
    }
}

