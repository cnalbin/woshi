import SwiftUI
import ImageIO

private actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private let images = NSCache<NSURL, UIImage>()
    init() { images.totalCostLimit = 12 * 1024 * 1024 }
    func image(at url: URL) -> UIImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 180,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let result = UIImage(cgImage: image)
        images.setObject(result, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        return result
    }
}

struct MealThumbnail: View {
    @Environment(\.appSkin) private var skin
    let url: URL?
    let symbol: String
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            skin.softAccent
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: symbol).font(.title3).foregroundStyle(skin.accent) }
        }.frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 13))
            .task(id: url) {
                image = nil
                if let url { image = await ThumbnailCache.shared.image(at: url) }
            }.accessibilityHidden(true)
    }
}
