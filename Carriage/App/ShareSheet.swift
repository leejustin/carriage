import SwiftUI
import UIKit

/// The system share sheet. Notes, Files, Mail and everything else the writer has installed show up here.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The Files app's "Save" picker, for keeping a copy of a page (or a folder of pages) outside Carriage.
struct FilesExporter: UIViewControllerRepresentable {
    var urls: [URL]
    var onSaved: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSaved: onSaved) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSaved: () -> Void

        init(onSaved: @escaping () -> Void) {
            self.onSaved = onSaved
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onSaved()
        }
    }
}
