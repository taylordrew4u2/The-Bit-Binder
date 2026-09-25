//
//  DocumentScannerView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import VisionKit

struct DocumentScannerView: View {
    let completion: ([UIImage]) -> Void

    static var isSupported: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        !ProcessInfo.processInfo.isiOSAppOnMac && VNDocumentCameraViewController.isSupported
        #endif
    }

    var body: some View {
        #if !targetEnvironment(macCatalyst)
        if Self.isSupported {
            DocumentCameraController(completion: completion)
        } else {
            unavailableView
        }
        #else
        unavailableView
        #endif
    }

    private var unavailableView: some View {
        CaptureUnavailableView(
            title: "Camera Scanning Unavailable",
            message: "Choose Photos or Files from Import Jokes instead."
        )
    }
}

#if !targetEnvironment(macCatalyst)
private struct DocumentCameraController: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: ([UIImage]) -> Void
        
        init(completion: @escaping ([UIImage]) -> Void) {
            self.completion = completion
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // VNDocumentCameraScan delivers images at full camera resolution
            // (12–48 MP on modern iPhones). Downscale each page to a maximum
            // long-edge of 2048 px before passing to the pipeline.
            // 2048 px is sufficient for Vision's accurate-level OCR and keeps
            // each page under ~12 MB vs 50–150 MB at native camera resolution.
            var images: [UIImage] = []
            images.reserveCapacity(scan.pageCount)
            for i in 0..<scan.pageCount {
                let raw = scan.imageOfPage(at: i)
                let downscaled: UIImage = autoreleasepool {
                    DocumentCameraController.downscale(raw, maxLongEdge: 2048) ?? raw
                }
                images.append(downscaled)
            }
            completion(images)
            controller.dismiss(animated: true)
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            #if DEBUG
            print("Document scanner failed: \(error)")
            #endif
            controller.dismiss(animated: true)
        }
    }

    // MARK: - Image Downscaling Helper

    /// Scales `image` so its longest edge is at most `maxLongEdge` points.
    /// Returns nil only if the CGContext could not be created (extremely unlikely).
    /// The returned image is always a fresh bitmap — it does not share backing store
    /// with the original so the original can be released immediately.
    static func downscale(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage? {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image } // already small enough

        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1          // always 1× pixels — we're specifying exact pixel size
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif

/// A dismissible fallback for unsupported hardware and restored presentations.
struct CaptureUnavailableView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}
