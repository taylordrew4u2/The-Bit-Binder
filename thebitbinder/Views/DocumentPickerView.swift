//
//  DocumentPickerView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    let completion: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            .image, .pdf, .text, .plainText, .utf8PlainText,
            .rtf, .rtfd,
            UTType(filenameExtension: "doc") ?? .text,
            UTType(filenameExtension: "docx") ?? .text,
            UTType(filenameExtension: "md") ?? .text,
            UTType(filenameExtension: "txt") ?? .text,
            .data  // fallback to accept any file
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        
        init(completion: @escaping ([URL]) -> Void) {
            self.completion = completion
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            print(" PICKER: User selected \(urls.count) files: \(urls.map { $0.lastPathComponent })")
            completion(urls)
        }
    }
}
