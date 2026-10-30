import SwiftUI
import UIKit

/// A file ready to be shared. `Identifiable` so it can drive `.sheet(item:)`.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Native iOS Share Sheet (includes "Save to Files"). `onFinish` reports whether
/// the user actually completed an action, so callers only record a backup date on success.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            DispatchQueue.main.async { onFinish(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
