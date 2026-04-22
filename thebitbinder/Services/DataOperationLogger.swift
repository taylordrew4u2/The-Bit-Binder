//
//  DataOperationLogger.swift
//  thebitbinder
//
//  Created for comprehensive logging of data operations
//

import Foundation
import SwiftData
import OSLog

/// Comprehensive logging service for all data operations to aid in debugging data loss issues
final class DataOperationLogger {
    
    static let shared = DataOperationLogger()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "The-BitBinder.thebitbinder", category: "DataOperations")
    private let logFileURL: URL
    private let maxLogFileSize: Int = 10 * 1024 * 1024 // 10MB
    private let maxLogFiles = 5
    
    init() {
        // Create log file in Application Support
        self.logFileURL = URL.applicationSupportDirectory
            .appending(path: "DataOperations.log")
        
        // Ensure log directory exists
        try? FileManager.default.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        logOperation(.info, "DataOperationLogger initialized")
    }
    
    // MARK: - Public Logging Interface
    
    func logDataCreation<T: PersistentModel>(_ entity: T, context: ModelContext) {
        let entityName = String(describing: type(of: entity))
        let message = "CREATED \(entityName)"
        logOperation(.info, message)
        
        // Log to system logger as well
        logger.info(" \(message)")
    }
    
    func logBulkOperation(_ operation: String, entityType: String, count: Int, context: ModelContext) {
        let message = "BULK_\(operation.uppercased()) \(count) \(entityType) entities"
        logOperation(.notice, message)
        
        logger.notice(" \(message)")
    }
    
    func logError(_ error: Error, operation: String, context: String? = nil) {
        let contextStr = context.map { " (\($0))" } ?? ""
        let message = "ERROR in \(operation)\(contextStr): \(error.localizedDescription)"
        logOperation(.error, message)
        
        logger.error(" \(message)")
    }
    
    func logCritical(_ message: String) {
        logOperation(.critical, "CRITICAL: \(message)")
        logger.critical(" CRITICAL: \(message)")
    }
    
    // MARK: - Internal Logging
    
    func logOperation(_ level: LogLevel, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue)] \(message)\n"
        
        // Write to file
        writeToLogFile(logLine)
        
        // Also print to console in debug builds
        #if DEBUG
        print(" [DataLog] \(logLine.trimmingCharacters(in: .newlines))")
        #endif
    }
    
    private func writeToLogFile(_ logLine: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Check if we need to rotate the log file
                if self.shouldRotateLogFile() {
                    self.rotateLogFile()
                }
                
                // Append to current log file
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    let fileHandle = try FileHandle(forWritingTo: self.logFileURL)
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(logLine.data(using: .utf8) ?? Data())
                    fileHandle.closeFile()
                } else {
                    try logLine.write(to: self.logFileURL, atomically: true, encoding: .utf8)
                }
                
            } catch {
                print("Failed to write to log file: \(error)")
            }
        }
    }
    
    private func shouldRotateLogFile() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attributes[.size] as? Int else {
            return false
        }
        return fileSize > maxLogFileSize
    }
    
    private func rotateLogFile() {
        do {
            // Move current log to rotated log
            let rotatedURL = logFileURL.appendingPathExtension("1")
            
            // Remove oldest rotated logs
            for i in stride(from: maxLogFiles, through: 2, by: -1) {
                let oldURL = logFileURL.appendingPathExtension("\(i)")
                let newURL = logFileURL.appendingPathExtension("\(i + 1)")
                
                if FileManager.default.fileExists(atPath: oldURL.path) {
                    if i == maxLogFiles {
                        try FileManager.default.removeItem(at: oldURL)
                    } else {
                        try FileManager.default.moveItem(at: oldURL, to: newURL)
                    }
                }
            }
            
            // Move current to .1
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                try FileManager.default.moveItem(at: logFileURL, to: rotatedURL)
            }
            
        } catch {
            print("Failed to rotate log file: \(error)")
        }
    }
    
}

// MARK: - Supporting Types

enum LogLevel: String, CaseIterable {
    case info = "INFO"
    case notice = "NOTICE"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
}

// Extension for public access to logging methods
extension DataOperationLogger {
    func logInfo(_ message: String) {
        logOperation(.info, message)
    }
    
    func logSuccess(_ message: String) {
        logOperation(.notice, "SUCCESS: \(message)")
        logger.notice(" SUCCESS: \(message)")
    }
}
