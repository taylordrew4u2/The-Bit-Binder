//
//  OCRTextExtractor.swift
//  thebitbinder
//
//  Enhanced OCR extraction with line-level metadata and confidence scoring
//

import Foundation
import Vision
import VisionKit
import UIKit
import PDFKit

// ExtractionError is defined in PDFTextExtractor.swift

/// Enhanced OCR text extraction that preserves layout, positioning, and confidence information
final class OCRTextExtractor {
    
    static let shared = OCRTextExtractor()
    private let customWordsProvider = OCRCustomWordsProvider()
    
    private init() {}
    
    // MARK: - PDF OCR Extraction
    
    func extractFromPDF(url: URL) async throws -> [NormalizedPage] {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.invalidDocument
        }
        
        var pages: [NormalizedPage] = []
        let pageCount = document.pageCount
        
        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            
            // Render the page to an image inside an autoreleasepool so the
            // UIImage and its backing CGImage are released immediately after
            // we hand the CGImage off to Vision — we never hold all page
            // images in memory simultaneously.
            let extractedPage: NormalizedPage? = try await {
                // Step 1: render inside pool, extract CGImage, release UIImage
                guard let cgImage: CGImage = autoreleasepool(invoking: {
                    convertPDFPageToImage(page)?.cgImage
                }) else { return nil }

                // Step 2: run Vision on the CGImage (UIImage is already gone)
                return try await extractFromCGImage(cgImage, pageNumber: i + 1)
            }()
            
            if let ep = extractedPage { pages.append(ep) }
        }
        
        return identifyRepeatingElements(pages: pages)
    }
    
    // MARK: - Image OCR Extraction

    /// Public entry point when caller already has a UIImage (e.g. camera scan).
    func extractFromImage(_ image: UIImage, pageNumber: Int = 1) async throws -> NormalizedPage {
        guard let cgImage = image.cgImage else {
            throw ExtractionError.invalidImage
        }
        // Pass image size separately so the UIImage can be freed by the caller
        // before the async Vision request starts.
        return try await extractFromCGImage(cgImage, pageNumber: pageNumber, sourceSize: image.size)
    }

    /// Core extraction path that works directly from a CGImage, avoiding the
    /// need to keep a UIImage alive across the async Vision call.
    func extractFromCGImage(_ cgImage: CGImage, pageNumber: Int = 1, sourceSize: CGSize? = nil) async throws -> NormalizedPage {
        let customWords = await customWordsProvider.getCustomWords()
        
        // Configure high-quality OCR request
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        
        // Set custom words if available
        if !customWords.allWords.isEmpty {
            request.customWords = customWords.allWords
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        try requestHandler.perform([request])
        
        let imageSize = sourceSize ?? CGSize(width: cgImage.width, height: cgImage.height)

        guard let observations = request.results, !observations.isEmpty else {
            return try await fallbackExtraction(cgImage: cgImage, pageNumber: pageNumber, customWords: customWords, imageSize: imageSize)
        }
        
        let extractedLines = processVisionResultsFromCGImage(observations, cgImageSize: imageSize, pageNumber: pageNumber)
        
        return NormalizedPage(
            pageNumber: pageNumber,
            lines: extractedLines,
            hasRepeatingHeader: false,
            hasRepeatingFooter: false,
            averageLineHeight: calculateAverageLineHeight(extractedLines),
            pageHeight: Float(imageSize.height)
        )
    }
    
    // MARK: - Vision Results Processing

    /// Primary overload — takes only the size so the UIImage is not retained.
    private func processVisionResultsFromCGImage(
        _ observations: [VNRecognizedTextObservation],
        cgImageSize: CGSize,
        pageNumber: Int
    ) -> [ExtractedLine] {
        
        var extractedLines: [ExtractedLine] = []
        
        // Sort observations by Y position (top to bottom)
        let sortedObservations = observations.sorted {
            $0.boundingBox.origin.y > $1.boundingBox.origin.y
        }
        
        let imageHeight = cgImageSize.height
        let imageWidth  = cgImageSize.width

        for (index, observation) in sortedObservations.enumerated() {
            guard let candidate = observation.topCandidates(1).first else { continue }
            
            let rawText        = candidate.string
            let normalizedText = normalizeOCRText(rawText)
            
            let visionBox = observation.boundingBox
            let boundingBox = CGRect(
                x: visionBox.origin.x * imageWidth,
                y: (1.0 - visionBox.origin.y - visionBox.height) * imageHeight,
                width: visionBox.width * imageWidth,
                height: visionBox.height * imageHeight
            )
            
            extractedLines.append(ExtractedLine(
                rawText: rawText,
                normalizedText: normalizedText,
                pageNumber: pageNumber,
                lineNumber: index + 1,
                boundingBox: boundingBox,
                confidence: candidate.confidence,
                estimatedFontSize: Float(boundingBox.height * 0.8),
                indentationLevel: calculateIndentationLevel(rawText),
                yPosition: Float(boundingBox.origin.y),
                method: .visionOCR
            ))
        }
        
        return extractedLines
    }
    
    // MARK: - Fallback Extraction
    
    private func fallbackExtraction(
        cgImage: CGImage,
        pageNumber: Int,
        customWords: OCRCustomWords,
        imageSize: CGSize? = nil
    ) async throws -> NormalizedPage {
        
        let fastRequest = VNRecognizeTextRequest()
        fastRequest.recognitionLevel = .fast
        fastRequest.usesLanguageCorrection = true
        
        if !customWords.allWords.isEmpty {
            fastRequest.customWords = customWords.allWords
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try requestHandler.perform([fastRequest])
        
        guard let observations = fastRequest.results, !observations.isEmpty else {
            throw ExtractionError.noTextFound
        }

        let size = imageSize ?? CGSize(width: cgImage.width, height: cgImage.height)
        let extractedLines = processVisionResultsFromCGImage(observations, cgImageSize: size, pageNumber: pageNumber)
        
        return NormalizedPage(
            pageNumber: pageNumber,
            lines: extractedLines,
            hasRepeatingHeader: false,
            hasRepeatingFooter: false,
            averageLineHeight: calculateAverageLineHeight(extractedLines),
            pageHeight: Float(cgImage.height)
        )
    }
    
    // MARK: - Helper Methods
    
    private func convertPDFPageToImage(_ page: PDFPage) -> UIImage? {
        let pageSize = page.bounds(for: .mediaBox).size
        let pageRotation = CGFloat(page.rotation)
        
        // Determine the size of the rendered image, accounting for rotation
        let imageSize = (pageRotation == 90 || pageRotation == 270)
            ? CGSize(width: pageSize.height, height: pageSize.width)
            : pageSize

        // 2× is sufficient for accurate OCR and halves peak memory vs 3×.
        // A standard A4 page at 2× is ~1240×1754 px (~8 MB) vs ~35 MB at 3×.
        let scale: CGFloat = 2.0
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: scaledSize))
            
            // Move origin to center for rotation
            ctx.cgContext.translateBy(x: scaledSize.width / 2.0, y: scaledSize.height / 2.0)
            // Apply rotation
            ctx.cgContext.rotate(by: -pageRotation * .pi / 180)
            // Scale for rendering
            ctx.cgContext.scaleBy(x: scale, y: -scale)

            // PDF drawing is based on the mediaBox. Translate so its center lands on the origin
            let mediaBox = page.bounds(for: .mediaBox)
            ctx.cgContext.translateBy(x: -mediaBox.midX, y: -mediaBox.midY)
            
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        
        // The image is now correctly rotated, but we still normalize to fix any EXIF orientation issues.
        return image.normalized()
    }
    
    private func normalizeOCRText(_ text: String) -> String {
        var normalized = text
        
        // Fix common OCR errors
        normalized = normalized.replacingOccurrences(of: "|", with: "I") // Common I/| confusion
        normalized = normalized.replacingOccurrences(of: "0", with: "O") // In text contexts where 0 should be O
        normalized = normalized.replacingOccurrences(of: "5", with: "S") // In text contexts where 5 should be S
        
        // Clean up whitespace
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return normalized
    }
    
    private func calculateIndentationLevel(_ text: String) -> Int {
        var leadingSpaces = 0
        for char in text {
            if char == " " {
                leadingSpaces += 1
            } else if char == "\t" {
                leadingSpaces += 4
            } else {
                break
            }
        }
        return max(0, leadingSpaces / 4)
    }
    
    private func calculateAverageLineHeight(_ lines: [ExtractedLine]) -> Float {
        guard !lines.isEmpty else { return 16.0 }
        
        let totalHeight = lines.reduce(0) { sum, line in
            sum + Float(line.boundingBox.height)
        }
        
        return totalHeight / Float(lines.count)
    }
    
    private func identifyRepeatingElements(pages: [NormalizedPage]) -> [NormalizedPage] {
        guard pages.count > 1 else { return pages }
        
        // Similar logic to PDF extractor for consistency
        var potentialHeaders: [String] = []
        var potentialFooters: [String] = []
        
        for page in pages {
            // Check top 2 lines for headers
            if let firstLine = page.lines.first?.normalizedText, !firstLine.isEmpty {
                potentialHeaders.append(firstLine)
            }
            if page.lines.count > 1 {
                let secondLine = page.lines[1].normalizedText
                if !secondLine.isEmpty {
                    potentialHeaders.append(secondLine)
                }
            }
            
            // Check bottom 2 lines for footers
            if let lastLine = page.lines.last?.normalizedText, !lastLine.isEmpty {
                potentialFooters.append(lastLine)
            }
            if page.lines.count > 1 {
                let secondLastLine = page.lines[page.lines.count - 2].normalizedText
                if !secondLastLine.isEmpty {
                    potentialFooters.append(secondLastLine)
                }
            }
        }
        
        let headerCounts = Dictionary(grouping: potentialHeaders, by: { $0 }).mapValues { $0.count }
        let footerCounts = Dictionary(grouping: potentialFooters, by: { $0 }).mapValues { $0.count }
        
        let repeatingHeader = headerCounts.first { $0.value >= pages.count / 2 }?.key
        let repeatingFooter = footerCounts.first { $0.value >= pages.count / 2 }?.key
        
        return pages.map { page in
            let hasHeader = repeatingHeader != nil &&
                           (page.lines.first?.normalizedText == repeatingHeader ||
                            (page.lines.count > 1 && page.lines[1].normalizedText == repeatingHeader))
            
            let hasFooter = repeatingFooter != nil &&
                           (page.lines.last?.normalizedText == repeatingFooter ||
                            (page.lines.count > 1 && page.lines[page.lines.count - 2].normalizedText == repeatingFooter))
            
            return NormalizedPage(
                pageNumber: page.pageNumber,
                lines: page.lines,
                hasRepeatingHeader: hasHeader,
                hasRepeatingFooter: hasFooter,
                averageLineHeight: page.averageLineHeight,
                pageHeight: page.pageHeight
            )
        }
    }
}

// MARK: - Custom Words Provider

final class OCRCustomWordsProvider {
    
    func getCustomWords() async -> OCRCustomWords {
        // In a real implementation, these would be loaded from the user's existing jokes
        // For now, return default comedy terms
        
        return OCRCustomWords(
            jokeTitle: [],
            venueName: [],
            comedyTerms: OCRCustomWords.defaultComedyTerms,
            userSlang: []
        )
    }
}
