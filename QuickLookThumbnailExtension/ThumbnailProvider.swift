import AppKit
import QuickLookThumbnailing
import os.log

private let logger = Logger(
    subsystem: Bundle(for: ThumbnailProvider.self).bundleIdentifier
        ?? "org.slicercompanion.thumbnail",
    category: "ThumbnailProvider"
)

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {

        logger.debug(
            "Providing thumbnail for: \(request.fileURL.path, privacy: .public)"
        )

        guard
            let cgImage = try? ThumbnailExtractor.extractThumbnail(
                from: request.fileURL, maxSize: request.maximumSize)
        else {
            logger.warning("No valid thumbnail found; returning empty reply.")
            handler(nil, nil)
            return
        }

        // Calculate the proper size preserving aspect ratio
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let maxSize = request.maximumSize

        let widthRatio = maxSize.width / imageSize.width
        let heightRatio = maxSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio, 1.0)  // Don't upscale

        let thumbnailSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        let reply = QLThumbnailReply(
            contextSize: thumbnailSize,
            currentContextDrawing: { () -> Bool in
                let image = NSImage(cgImage: cgImage, size: thumbnailSize)
                image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                return true
            }
        )

        handler(reply, nil)
    }
}
