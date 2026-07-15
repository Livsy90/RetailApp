import Foundation
import ImageIO
import UIKit

struct LoadedImage: @unchecked Sendable {
    let image: UIImage
}

actor ImagePipeline {
    private let memoryCache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<LoadedImage, Error>] = [:]

    init(memoryCostLimit: Int = 48 * 1_024 * 1_024) {
        memoryCache.totalCostLimit = memoryCostLimit
    }

    func image(url: URL, targetSize: CGSize, scale: CGFloat) async throws -> LoadedImage {
        let key = Self.key(url: url, targetSize: targetSize, scale: scale)
        
        if let cached = memoryCache.object(forKey: key as NSString) {
            return LoadedImage(image: cached)
        }
        
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task<LoadedImage, Error> {
            let (data, response) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            if let response = response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw URLError(.badServerResponse)
            }
            let image = try Self.downsample(data: data, targetSize: targetSize, scale: scale)
            return LoadedImage(image: image)
        }
        
        inFlight[key] = task

        do {
            let loaded = try await task.value
            inFlight[key] = nil
            let pixels = loaded.image.size.width * loaded.image.size.height * loaded.image.scale * loaded.image.scale
            memoryCache.setObject(loaded.image, forKey: key as NSString, cost: Int(pixels * 4))
            return loaded
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    private nonisolated static func key(url: URL, targetSize: CGSize, scale: CGFloat) -> String {
        "\(url.absoluteString)|\(Int(targetSize.width))x\(Int(targetSize.height))|@\(scale)"
    }

    private nonisolated static func downsample(data: Data, targetSize: CGSize, scale: CGFloat) throws -> UIImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw URLError(.cannotDecodeContentData)
        }

        let maxDimension = max(targetSize.width, targetSize.height) * scale
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        return UIImage(
            cgImage: cgImage,
            scale: scale,
            orientation: .up
        )
    }
}
