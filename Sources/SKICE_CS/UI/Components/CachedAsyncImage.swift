import SwiftUI
import UIKit

/// Drop-in replacement for AsyncImage that routes through ImageManager
/// (deduplicated downloads plus memory/disk caching). The content closure keeps
/// AsyncImage's AsyncImagePhase API so existing call sites change in name only.
public struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    public init(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = content
    }

    public var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else {
                    phase = .failure(ImageLoadFailure.missingURL)
                    return
                }
                if let image = ImageManager.shared.image(for: url) {
                    phase = .success(Image(uiImage: image))
                    return
                }
                if let image = await ImageManager.shared.load(for: url) {
                    phase = .success(Image(uiImage: image))
                } else {
                    phase = .failure(ImageLoadFailure.downloadFailed)
                }
            }
    }
}

private enum ImageLoadFailure: Error {
    case missingURL
    case downloadFailed
}
