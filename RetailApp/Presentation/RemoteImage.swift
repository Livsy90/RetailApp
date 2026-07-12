import SwiftUI

enum RemoteImagePlaceholder {
    case hero
    case campaign
    case product
    case recommendation
    case editorial
}

struct RemoteImage: View {
    let url: URL?
    let targetSize: CGSize
    let pipeline: ImagePipeline
    let placeholder: RemoteImagePlaceholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderView
            }
        }
        .clipped()
        .task(id: requestID) {
            guard let url else { return }
            do {
                let loaded = try await pipeline.image(
                    url: url,
                    targetSize: targetSize,
                    scale: displayScale
                )
                try Task.checkCancellation()
                image = loaded.image
            } catch is CancellationError {
                return
            } catch {
                image = nil
            }
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        switch placeholder {
        case .hero:
            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .campaign:
            LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .product:
            Color.gray.opacity(0.15).overlay { Image(systemName: "photo") }
        case .recommendation:
            Color.purple.opacity(0.12).overlay { Image(systemName: "sparkles") }
        case .editorial:
            Color.brown.opacity(0.12)
        }
    }

    private var requestID: String {
        "\(url?.absoluteString ?? "none")|\(Int(targetSize.width))x\(Int(targetSize.height))|@\(displayScale)"
    }
}
