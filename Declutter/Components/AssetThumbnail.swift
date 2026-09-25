import Photos
import SwiftUI

/// Loads a thumbnail for a photo library asset, sized to fit the view.
struct AssetThumbnail: View {
    let asset: PHAsset
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.tertiarySystemFill)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: asset.localIdentifier) {
                let pixels = CGSize(
                    width: geometry.size.width * displayScale,
                    height: geometry.size.height * displayScale
                )
                let loaded = await ThumbnailLoader.image(for: asset, targetSize: pixels)
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            }
        }
    }
}

enum ThumbnailLoader {
    private static let manager = PHCachingImageManager()

    static func image(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        let options = PHImageRequestOptions()
        // High quality + fast resize delivers exactly one image, which is what an async function needs.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
