import SwiftUI
import UIKit

/// Reuses the exact storyboard iOS displays during launch. Separate SwiftUI
/// copies can shift as safe areas, fonts and the tab bar settle into place.
struct LaunchSplashView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIStoryboard(name: "LaunchScreen", bundle: .main)
            .instantiateInitialViewController() ?? UIViewController()
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
