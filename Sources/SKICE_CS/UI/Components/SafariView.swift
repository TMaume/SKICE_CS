import SafariServices
import SwiftUI

/// A `UIViewControllerRepresentable` wrapper around `SFSafariViewController`
/// allowing users to securely access external web pages (such as Steam's API key portal)
/// without leaving the application.
public struct SafariView: UIViewControllerRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: configuration)
        // Match the dark gunmetal and CS orange palette
        controller.preferredBarTintColor = UIColor(red: 0.067, green: 0.078, blue: 0.110, alpha: 1.0)
        controller.preferredControlTintColor = UIColor(red: 0.898, green: 0.557, blue: 0.149, alpha: 1.0)
        controller.dismissButtonStyle = .done
        return controller
    }

    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}